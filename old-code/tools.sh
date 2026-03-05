#!/usr/bin/env nix-shell
#! nix-shell -i bash --pure
#! nix-shell -p bash cacert curl jq direnv gettext
#! nix-shell -I nixpkgs=https://github.com/NixOS/nixpkgs/tarball/nixos-24.05

USER_BIN_DIR="${HOME}/.local/bin"

function linux_tools() {
    mkdir -p ${USER_BIN_DIR}
    # echo "export PATH=\$PATH:\$USER_BIN_DIR" | tee -a ~/.bashrc
    # echo ". ~/.bash_aliases" | tee -a ~/.bashrc
    curl -sSLO https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux64
    install -m 0755 jq-linux64 jq && rm -f jq-linux64

    DIRENV_VERSION=$(curl -sL https://api.github.com/repos/direnv/direnv/releases/latest | jq -r ".tag_name")
    curl -sSLO https://github.com/direnv/direnv/releases/download/${DIRENV_VERSION}/direnv.linux-amd64
    install -m 0755 direnv.linux-amd64 ${USER_BIN_DIR}/direnv && rm -f direnv.linux-amd64
    # ${USER_BIN_DIR}/direnv hook bash | tee -a ${HOME}/.bash_aliases

    curl -sSLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -m 0755 kubectl ${USER_BIN_DIR}/kubectl && rm -f kubectl

    K3D_VERSION=$(curl -sL https://api.github.com/repos/k3d-io/k3d/releases/latest | jq -r ".tag_name")
    curl -sSLO https://github.com/k3d-io/k3d/releases/download/${K3D_VERSION}/k3d-linux-amd64
    install -m 0755 k3d-linux-amd64 ${USER_BIN_DIR}/k3d && rm -f k3d-linux-amd64

    K3D_VERSION=$(curl -sL https://api.github.com/repos/cnrancher/autok3s/releases/latest | jq -r ".tag_name")
    curl -sSLO https://github.com/cnrancher/autok3s/releases/download/${K3D_VERSION}/autok3s_linux_amd64
    install -m 0755 autok3s_linux_amd64 ${USER_BIN_DIR}/autok3s && rm -f autok3s_linux_amd64

    FLUX_VERSION=$(curl -sL https://api.github.com/repos/fluxcd/flux2/releases/latest | jq -r ".tag_name")
    curl -sSLO https://github.com/fluxcd/flux2/releases/download/${FLUX_VERSION}/flux_${FLUX_VERSION/v/}_linux_amd64.tar.gz
    tar xf flux_${FLUX_VERSION/v/}_linux_amd64.tar.gz
    install -m 0755 flux ${USER_BIN_DIR}/flux && rm -f flux flux_${FLUX_VERSION/v/}_linux_amd64.tar.gz

    AGE_VERSION=$(curl -sL https://api.github.com/repos/FiloSottile/age/releases/latest | jq -r ".tag_name")
    curl -sSLO https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/age-${AGE_VERSION}-linux-amd64.tar.gz
    tar xf age-${AGE_VERSION}-linux-amd64.tar.gz
    install -m 0755 age/age ${USER_BIN_DIR}/age && rm -rf age*

    SOPS_VERSION=$(curl -sL https://api.github.com/repos/getsops/sops/releases/latest | jq -r ".tag_name")
    curl -sSLO https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.amd64
    install -m 0755 sops-${SOPS_VERSION}.linux.amd64 ${USER_BIN_DIR}/sops && rm -f sops-${SOPS_VERSION}.linux.amd64

    CLOUDFLARED_VERSION=$(curl -sL https://api.github.com/repos/cloudflare/cloudflared/releases/latest | jq -r ".tag_name")
    curl -sSLO https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-amd64
    install -m 0755 cloudflared-linux-amd64 ${USER_BIN_DIR}/cloudflared && rm -f cloudflared-linux-amd64

    curl -sSL -o devspace "https://github.com/loft-sh/devspace/releases/latest/download/devspace-linux-amd64"
    install -c -m 0755 devspace ${USER_BIN_DIR}/devspace && rm -f devspace

    curl -sSL -o vcluster "https://github.com/loft-sh/vcluster/releases/latest/download/vcluster-linux-amd64"
    install -c -m 0755 vcluster ${USER_BIN_DIR}/vcluster && rm -f vcluster

    curl -sSL -o argocd "https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64"
    install -c -m 0755 argocd ${USER_BIN_DIR}/argocd && rm -f argocd
}

linux_tools
