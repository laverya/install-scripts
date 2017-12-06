#!/bin/bash

set -e

AIRGAP=0
DAEMON_TOKEN=
GROUP_ID=
LOG_LEVEL=
MIN_DOCKER_VERSION="1.10.3" # k8s min
NO_PROXY=1
PINNED_DOCKER_VERSION="{{ pinned_docker_version }}"

PUBLIC_ADDRESS=
PRIVATE_ADDRESS=
REGISTRY_BIND_PORT=
SKIP_DOCKER_INSTALL=0
SKIP_DOCKER_PULL=0
TLS_CERT_PATH=
UI_BIND_PORT=8800
USER_ID=

BOOTSTRAP_TOKEN=
BOOTSTRAP_TOKEN_TTL="24h"
KUBERNETES_NAMESPACE="default"
KUBERNETES_VERSION="{{ kubernetes_version }}"

{% include 'common/common.sh' %}
{% include 'common/prompt.sh' %}
{% include 'common/system.sh' %}
{% include 'common/docker.sh' %}
{% include 'common/docker-version.sh' %}
{% include 'common/docker-install.sh' %}
{% include 'common/replicated.sh' %}
{% include 'common/cli-script.sh' %}
{% include 'common/alias.sh' %}
{% include 'common/ip-address.sh' %}
{% include 'common/proxy.sh' %}
{% include 'common/airgap.sh' %}
{% include 'common/log.sh' %}
{% include 'common/kubernetes.sh' %}

initKube() {
    logStep "Verify Kubelet"
    if ! ps aux | grep -qE "[k]ubelet"; then
        logStep "Initialize Kubernetes"
        set +e

        kubeadm init \
            --skip-preflight-checks \
            --kubernetes-version $KUBERNETES_VERSION \
            --token $BOOTSTRAP_TOKEN \
            --token-ttl ${BOOTSTRAP_TOKEN_TTL} \
            --apiserver-cert-extra-sans $PUBLIC_ADDRESS
        _status=$?
        set -e
        if [ "$_status" -ne "0" ]; then
            printf "${RED}Failed to initialize the kubernetes cluster.${NC}\n" 1>&2
            exit $_status
        fi
    fi
    cp /etc/kubernetes/admin.conf $HOME/admin.conf
    chown $SUDO_USER:$SUDO_USER $HOME/admin.conf


    # TODO this all needs work, maybe move some to end
    export KUBECONFIG=/etc/kubernetes/admin.conf
#    echo 'export KUBECONFIG=/etc/kubernetes/admin.conf' >> $HOME/.profile
#    echo 'alias k=/usr/bin/kubectl' >> $HOME/.profile
#    echo 'alias replicatedctl=/usr/bin/kubectl exec -it $(kubectl get pods -ltier=master -lapp=replicated -o jsonpath="{.metadata.name}") replicatedctl' >> $HOME/.profile
#    if [ -n $PRIVATE_ADDRESS ] && [ -n $PUBLIC_ADDRESS ]; then
#        safesed $PRIVATE_ADDRESS $PUBLIC_ADDRESS $HOME/admin.conf
#        logSuccess "modify admin.conf kubeconfig for remote access"
#    fi

    logSuccess "Kubernetes Master Initialized"
}


maybeGenerateBootstrapToken() {
    if [ -z "$BOOTSTRAP_TOKEN" ]; then
        logStep "generate kubernetes bootstrap token"
        BOOTSTRAP_TOKEN=$(kubeadm token generate)
    fi
    echo "Kubernetes bootstrap token: ${BOOTSTRAP_TOKEN}"
    echo "This token will expire in 24 hours"

    # if kubelet is already running this is another run of the isntall script,
    # so create the token in k8s api
    if ps aux | grep -qE "[k]ubelet"; then
        kubeadm token create $BOOTSTRAP_TOKEN --ttl ${BOOTSTRAP_TOKEN_TTL}
    fi

    logSuccess "bootstrap token set"
}


ensureCNIPortMapping() {
    # todo allow force reinstall CNI
    if [ ! -d /tmp/cni-plugins ]; then


        logStep "configure CNI Port Mapping"
        pushd /tmp && mkdir cni-plugins && cd cni-plugins && \
        wget https://github.com/containernetworking/plugins/releases/download/v0.6.0-rc1/cni-plugins-amd64-v0.6.0-rc1.tgz && \
        tar zxfv cni-plugins-amd64-v0.6.0-rc1.tgz
        cp /tmp/cni-plugins/portmap /opt/cni/bin/
        mkdir -p /etc/cni/net.d
        sudo sh -c 'cat >/etc/cni/net.d/10-mynet.conflist <<-EOF
    {
        "cniVersion": "0.3.0",
        "name": "replicated-cni",
          "plugins": [
            {
                "name": "weave",
                "type": "weave-net",
                "hairpinMode": true
            },
            {
                "type": "portmap",
                "capabilities": {"portMappings": true},
                "snat": true
            }
        ]
    }
    EOF'
        rm /etc/cni/net.d/10-weave.conf || :
        popd
    fi
    logStep "CNI configured for port mapping"
}
weavenetDeploy() {
    logStep "deploy weave network"

    getUrlCmd
#    $URLGET_CMD "{{ replicated_install_url }}/{{ kubernetes_weave_path }}?{{ kubernetes_weave_query }}" \
    $URLGET_CMD https://git.io/weave-kube-1.6 \
        > /tmp/weave.yml
    kubectl apply -f /tmp/weave.yml -n kube-system
    logSuccess "weave network deployed"
}

deployDashboard() {
    logStep "deploy kubernetes dashboard"
    kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -n kube-system -f https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/kubernetes-dashboard.yaml
    logSuccess "kubernetes dashboard deployed"
}

untaintMaster() {
    logStep "remove NoSchedule taint from master node"
    kubectl --kubeconfig=admin.conf taint nodes --all node-role.kubernetes.io/master:NoSchedule- || \
        echo "Taint not found or already removed. The above error can be ignored."
    logSuccess "master taint removed"
}

kubernetesDeploy() {
    logStep "deploy replicated components"

    getUrlCmd
    $URLGET_CMD "{{ replicated_install_url }}/{{ kubernetes_manifests_path }}?{{ kubernetes_manifests_query }}" \
        > /tmp/kubernetes.yml

    kubectl apply -f /tmp/kubernetes.yml -n $KUBERNETES_NAMESPACE

    logStep "patch replicated serviceAccount"
    kubectl -n $KUBERNETES_NAMESPACE patch deploy/replicated -p '{"spec": {"template": {"spec": {"serviceAccountName": "default"}}}}'
    logStep "patch replicated hostPort"
    kubectl -n $KUBERNETES_NAMESPACE patch deploy replicated -p "{\"spec\": {\"template\": {\"spec\": {\"hostNetwork\": true, \"containers\": [{\"name\": \"replicated-ui\", \"ports\": [{\"containerPort\": 8800, \"hostPort\": $UI_BIND_PORT}]}]}}}}"
    kubectl -n $KUBERNETES_NAMESPACE get pods,svc
    logSuccess "Replicated master"
}

createPVs() {
    logStep "Skip Persistent Volumes"
    logSuccess "Great!"
}

createServiceAccount() {
    logStep "Create service account"
    echo '
---
apiVersion: v1
kind: List
items:
  - metadata:
      labels:
        name: replicated
      name: replicated
    apiVersion: v1
    kind: ServiceAccount
  - metadata:
      labels:
        name: replicated
      name: replicated
      namespace: kube-system
    apiVersion: v1
    kind: ServiceAccount
  - apiVersion: rbac.authorization.k8s.io/v1beta1
    kind: ClusterRoleBinding
    metadata:
      name: replicated-admin
      namespace: default
    roleRef:
      kind: ClusterRole
      name: cluster-admin
      apiGroup: rbac.authorization.k8s.io
    subjects:
      - kind: ServiceAccount
        name: replicated
        namespace: default
      - kind: ServiceAccount
        name: replicated
        namespace: kube-system
      - kind: ServiceAccount
        name: default
        namespace: default
      - kind: ServiceAccount
        name: default
        namespace: kube-system
' | kubectl apply -f -

  logSuccess "default service account updated"
}


getHelm() {
    if ! commandExists /usr/local/bin/helm; then
        logStep "Install Helm"

        getUrlCmd
        $URLGET_CMD https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get \
            > /tmp/get_helm.sh
        chmod 700 /tmp/get_helm.sh
        /tmp/get_helm.sh
    fi
    logSuccess "Helm installed"

    if [ ! -d $HOME/.helm ]; then
        logStep "Initialize Helm & Tiller"
        helm init
        kubectl -n kube-system patch deploy/tiller-deploy -p '{"spec": {"template": {"spec": {"serviceAccountName": "default"}}}}'
    fi
    logSuccess "Helm initialized"
}

deployRookOperator() {
    logStep "Install rook operator chart"

    # TODO this chart is broken, but if they fix it we should use it instead of git
    #helm repo add rook http://charts.rook.io
    #helm install rook/rook-operator

    if ! helm get rook-operator >/dev/null 2>&1; then
        logStep "helm install repo"

        logStep "get rook release"
        pushd /tmp && rm -rf rook && mkdir rook && cd rook
        wget https://github.com/rook/rook/archive/v0.5.0.tar.gz
        tar zxfv v0.5.0.tar.gz
        ls /tmp/rook/rook-0.5.0/demo/helm/rook-operator
        popd

        pushd /tmp/rook/rook-0.5.0/demo/helm/rook-operator
        helm install --name rook-operator --namespace rook .
        popd
    fi

    logSuccess "installed rook/rook-operator"
}

deployNginxIngressController() {
    logStep "Install nginx ingress chart"

    if ! helm get nginx-ingress >/dev/null 2>&1; then
        helm install --name nginx-ingress stable/nginx-ingress
    fi

    logSuccess "installed stable/nginx-ingress"
}

createRookStorageClass() {
    logStep "Create Rook StorageClass"


    echo '
---
apiVersion: v1
kind: List
items:
    - apiVersion: rook.io/v1alpha1
      kind: Cluster
      metadata:
        name: rook
        namespace: rook
      spec:
        versionTag: master
        dataDirHostPath: /opt/replicated/rook
        storage:
          useAllNodes: true
          useAllDevices: false
          storeConfig:
            storeType: filestore
            databaseSizeMB: 1024
            journalSizeMB: 1024
    - apiVersion: rook.io/v1alpha1
      kind: Pool
      metadata:
        name: replicapool
        namespace: rook
      spec:
        replication:
          size: 1
    - apiVersion: storage.k8s.io/v1
      kind: StorageClass
      metadata:
         name: rook-block
      provisioner: rook.io/block
      parameters:
        pool: replicapool
' | kubectl apply -f -

    logSuccess "Rook Storage Class Created"


    # TODO the Daemon will need to copy the rook secret from this NS to the app namespace e.g.
    #
    #     kubectl get secret rook-rook-user -o json | jq '.metadata.namespace = "kube-system"' | kubectl apply -f -

}

outro() {
    echo
    if [ -z "$PUBLIC_ADDRESS" ]; then
        PUBLIC_ADDRESS="<this_server_address>"
    fi
    printf "\nTo continue the installation, visit the following URL in your browser:\n\n"
    printf "${GREEN}    https://%s:%s\n" "$PUBLIC_ADDRESS" "$UI_BIND_PORT"

    printf "\n"
    if ! commandExists "replicated"; then
        # TODO kubectl this thing
        printf "\nTo create an alias for the replicated cli command run the following in your current shell or log out and log back in:\n\n  source /etc/replicated.alias\n"
    fi
    printf "${NC}\n"
}


################################################################################
# Execution starts here
################################################################################

require64Bit
requireRootUser
detectLsbDist
detectInitSystem

while [ "$1" != "" ]; do
    _param="$(echo "$1" | cut -d= -f1)"
    _value="$(echo "$1" | grep '=' | cut -d= -f2-)"
    case $_param in
        airgap)
            # arigap implies "no proxy" and "skip docker"
            AIRGAP=1
            NO_PROXY=1
            SKIP_DOCKER_INSTALL=1
            ;;
        bypass-storagedriver-warnings|bypass_storagedriver_warnings)
            BYPASS_STORAGEDRIVER_WARNINGS=1
            ;;
        bootstrap-token|bootrap_token)
            BOOTSTRAP_TOKEN="$_value"
            ;;
        bootstrap-token-ttl|bootrap_token_ttl)
            BOOTSTRAP_TOKEN_TTL="$_value"
            ;;
        docker-version|docker_version)
            PINNED_DOCKER_VERSION="$_value"
            ;;
        http-proxy|http_proxy)
            PROXY_ADDRESS="$_value"
            ;;
        log-level|log_level)
            LOG_LEVEL="$_value"
            ;;
        no-docker|no_docker)
            SKIP_DOCKER_INSTALL=1
            ;;
        no-proxy|no_proxy)
            NO_PROXY=1
            ;;
        public-address|public_address)
            PUBLIC_ADDRESS="$_value"
            ;;
        private-address|private_address)
            PRIVATE_ADDRESS="$_value"
            ;;
        release-sequence|release_sequence)
            RELEASE_SEQUENCE="$_value"
            ;;
        skip-pull|skip_pull)
            SKIP_DOCKER_PULL=1
            ;;
        swarm-advertise-addr|swarm_advertise_addr)
            SWARM_ADVERTISE_ADDR="$_value"
            ;;
        swarm-listen-addr|swarm_listen_addr)
            SWARM_LISTEN_ADDR="$_value"
            ;;
        kubernetes-namespace|kubernetes_namespace)
            KUBERNETES_NAMESPACE="$_value"
            ;;
        ui-bind-port|ui_bind_port)
            UI_BIND_PORT="$_value"
            ;;
        *)
            echo >&2 "Error: unknown parameter \"$_param\""
            exit 1
            ;;
    esac
    shift
done

if [ "$AIRGAP" = "1" ]; then
    echo $AIRGAP
    bailNoAirgap
fi


if [ "$NO_PROXY" != "1" ]; then
    echo $NO_PROXY
    bailNoProxy
fi

if [ -n "$PROXY_ADDRESS" ]; then
    echo $PROXY_ADDRESS
    bailNoProxy
fi

if [ -z "$PUBLIC_ADDRESS" ] && [ "$AIRGAP" -ne "1" ]; then
    printf "Determining service address\n"
    discoverPublicIp

    if [ -n "$PUBLIC_ADDRESS" ]; then
        shouldUsePublicIp
    else
        printf "The installer was unable to automatically detect the service IP address of this machine.\n"
        printf "Please enter the address or leave blank for unspecified.\n"
        promptForPublicIp
    fi
fi

#if [ -z "$PRIVATE_ADDRESS" ] && [ "$AIRGAP" -ne "1" ]; then
#    promptForPrivateIp
#fi


if [ "$SKIP_DOCKER_INSTALL" != "1" ]; then
    installDocker "$PINNED_DOCKER_VERSION" "$MIN_DOCKER_VERSION"

    checkDockerDriver
    checkDockerStorageDriver
fi

if [ "$RESTART_DOCKER" = "1" ]; then
    restartDocker
fi

downloadComponentsApt
ensureCNIPortMapping

maybeGenerateBootstrapToken
initKube
weavenetDeploy
deployDashboard

createServiceAccount
untaintMaster
getHelm
deployRookOperator
createRookStorageClass

# still need to figure out how to dedupe these
 deployNginxIngressController

echo
kubectl get nodes
logSuccess "Kubernetes nodes"
echo

echo
kubectl get pods -n kube-system
logSuccess "Kubernetes system"
echo

echo
kubectl get pods -n rook
logSuccess "Rook Storage Manager"
echo

kubernetesDeploy
createPVs

# TODO ALIAS -- kubectl exec -it $(kubectl get pods -l tier=master | tail -n1) replicated replicatedctl
# printf "Installing replicated command alias\n"
# installCLIFile '"$(sudo docker inspect --format "{{ '{{.Status.ContainerStatus.ContainerID}}' }}" "$(sudo docker service ps "$(sudo docker service inspect --format "{{ '{{.ID}}' }}" '"${SWARM_STACK_NAMESPACE}"'_replicated)" -q | awk "NR==1")")"'
# installAliasFile


printf "\n"
printf "\n"
printf "To add a node to this cluster, run the following command:\n\n"
printf "${GREEN}    curl -sSL {{ replicated_install_url }}/{{ kubernetes_node_join_path }} | sudo bash -s \\ \n"
printf "        kubernetes-master-addr=%s \\ \n" "$PUBLIC_ADDRESS"
printf "        kubeadm-token=%s${NC}\n${NC}" "$BOOTSTRAP_TOKEN"

outro

printf "\n"
printf "\n"
printf "To access this cluster remotely via kubectl, you can download the admin kubeconfig from /etc/kubernetes:\n\n"
printf "$    scp $PUBLIC_ADDRESS:/etc/kubernetes/admin.conf ~/.kube/replicated.conf \n\n${NC}"
printf "Then you can use it with :\n\n"
printf "    kubectl --kubeconfig ~/.kube/replicated.conf get nodes \n"
printf "    kubectl --kubeconfig ~/.kube/replicated.conf get pods  \n"
printf "${NC}"

# TODO: wait for replicated services to come up

exit 0
