#######################################
# Print a "no airgap" message and exit 1
# Globals:
#   None
# Arguments:
#   Message
# Returns:
#   None
#######################################
bailNoAirgap() {
    bail "Airgapped Kubernetes installs are not supported at this time"
}

#######################################
# Print a "no proxy" message and exit 1
# Globals:
#   None
# Arguments:
#   Message
# Returns:
#   None
#######################################
bailNoProxy() {
    bail "Kubernetes installs behind a proxy are not supported at this time"
}



#######################################
# Download Components Using Apt. Debian/Ubuntu only
# Globals:
#   None
# Arguments:
#   Message
# Returns:
#   None
#######################################
downloadComponentsApt() {
    if commandExists "kubeadm"; then
        return
    fi

    logStep "Install kubernetes components"
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add
    cat <<EOF > /etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
    apt-get update
    apt-get install -y kubeadm kubelet kubectl kubernetes-cni ceph-common
    logSuccess "Kubernetes components downloaded"
}


