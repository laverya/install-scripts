#!/bin/bash

set -e

AIRGAP=0
MIN_DOCKER_VERSION="1.13.1" # secrets compatibility
NO_PROXY=1
PINNED_DOCKER_VERSION="{{ pinned_docker_version }}"
SKIP_DOCKER_INSTALL=0

{% include 'common/common.sh' %}
{% include 'common/prompt.sh' %}
{% include 'common/system.sh' %}
{% include 'common/docker.sh' %}
{% include 'common/docker-version.sh' %}
{% include 'common/docker-install.sh' %}
{% include 'common/docker-swarm.sh' %}
{% include 'common/replicated.sh' %}
{% include 'common/ip-address.sh' %}
{% include 'common/proxy.sh' %}
{% include 'common/log.sh' %}
{% include 'common/kubernetes.sh' %}

KUBERNETES_MASTER_PORT="6443"
KUBERNETES_MASTER_ADDR="{{ kubernetes_master_addr }}"
KUBEADM_TOKEN="{{ kubeadm_token }}"

joinKubernetes() {
    logStep "Verify Kubelet"
    if ! ps aux | grep -qE "[k]ubelet"; then
        logStep "Join Kubernetes Node"
        set +e
        kubeadm join --token "${KUBEADM_TOKEN}" "${KUBERNETES_MASTER_ADDR}:${KUBERNETES_MASTER_PORT}"
        _status=$?
        set -e
        if [ "$_status" -ne "0" ]; then
            printf "${RED}Failed to join the kubernetes cluster.${NC}\n" 1>&2
            exit $?
        fi
        logSuccess "Node Joined successfully"
    fi
    logSuccess "Node Kubelet Initalized"
}

promptForToken() {
    if [ -n "$KUBEADM_TOKEN" ]; then
        return
    fi

    printf "Please enter the kubernetes boostrap token.\n"
    while true; do
        printf "Kubernetes join token: "
        prompt
        if [ -n "$PROMPT_RESULT" ]; then
            KUBEADM_TOKEN="$PROMPT_RESULT"
            return
        fi
    done
}

promptForAddress() {
    if [ -n "$KUBERNETES_MASTER_ADDR" ]; then
        return
    fi

    printf "Please enter the Kubernetes master address.\n"
    printf "e.g. 10.128.0.4\n"
    while true; do
        printf "Kubernetes master address: "
        prompt
        if [ -n "$PROMPT_RESULT" ]; then
            KUBERNETES_MASTER_ADDR="$PROMPT_RESULT"
            return
        fi
    done
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
        ca)
            CA="$_value"
            ;;
        daemon-registry-address|daemon_registry_address)
            DAEMON_REGISTRY_ADDRESS="$_value"
            ;;
        docker-version|docker_version)
            PINNED_DOCKER_VERSION="$_value"
            ;;
        http-proxy|http_proxy)
            PROXY_ADDRESS="$_value"
            ;;
        no-docker|no_docker)
            SKIP_DOCKER_INSTALL=1
            ;;
        no-proxy|no_proxy)
            NO_PROXY=1
            ;;
        kubernetes-master-addr|kubernetes_master_addr)
            KUBERNETES_MASTER_ADDR="$_value"
            ;;
        kubeadm-token|kubeadm_token)
            KUBEADM_TOKEN="$_value"
            ;;
        tags)
            OPERATOR_TAGS="$_value"
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

if [ "$SKIP_DOCKER_INSTALL" != "1" ]; then
    installDocker "$PINNED_DOCKER_VERSION" "$MIN_DOCKER_VERSION"

    checkDockerDriver
    checkDockerStorageDriver
fi


if [ "$RESTART_DOCKER" = "1" ]; then
    restartDocker
fi


promptForAddress
promptForToken


downloadComponentsApt
joinKubernetes

exit 0
