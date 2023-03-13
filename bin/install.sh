#!/usr/bin/env bash

set -eu

__here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__root="$(cd "$(dirname "${__here}")" && pwd)"
__file="$(basename "${BASH_SOURCE[0]}")"


ARCH=amd64
if [ "$(uname -m)" = "arm64" ]; then ARCH=arm64; fi
BIN_HOME="${HOME}/.local/bin"
mkdir -p "$BIN_HOME"
KIND_VERSION="v0.17.0"

function usage
{
    echo "
Setup and run Kind k8s cluster with Cilium CNI.

Usage:
    ${__file} [options]

Options:
    --skip-hubble      Do not install Cilium Hubble
    -h, --help         Show this screen.
"
}

for arg in "$@"; do
  case $arg in
    -h|--help)
      usage
      exit 0
      ;;
    --skip-hubble)
      SKIP_HUBBLE="true"
      shift
      ;;
    *)
      echo "Invalid argument '$arg'"
      usage
      exit 1
      ;;
  esac
done


### Tools
if ! [ -x "$(command -v kubectl)" ]; then
  curl -L --output "${BIN_HOME}/kubectl" "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/${ARCH}/kubectl"
  chmod +x "${BIN_HOME}/kubectl"
fi
kubectl version --client

# Install kind if needed
if ! [ -x "$(command -v kind)" ]; then
  echo "Installing Kind binary..."
  echo "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-darwin-${ARCH}"
  curl -L --output "${BIN_HOME}/kind" "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-darwin-${ARCH}"
  chmod +x "${BIN_HOME}/kind"
fi
kind --version

# Install Cilium Cli if needed
if ! [ -x "$(command -v cilium)" ]; then
  echo "Installing Cilium Cli..."
  CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/master/stable.txt)
  curl -L --fail --remote-name-all "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-darwin-${ARCH}.tar.gz{,.sha256sum}"
  shasum -a 256 -c "cilium-darwin-${ARCH}.tar.gz.sha256sum"
  tar xzvfC "cilium-darwin-${ARCH}.tar.gz" $BIN_HOME
  rm cilium-darwin-${ARCH}.tar*
fi
cilium version

# Install Hubble Client
if [ -z "${SKIP_HUBBLE:-}" ] && ! [ -x "$(command -v hubble)" ]; then
  echo "Installing Cilium Hubble..."
  HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
  curl -L --fail --remote-name-all "https://github.com/cilium/hubble/releases/download/$HUBBLE_VERSION/hubble-darwin-${ARCH}.tar.gz{,.sha256sum}"
  shasum -a 256 -c "hubble-darwin-${ARCH}.tar.gz.sha256sum"
  tar xzvfC "hubble-darwin-${ARCH}.tar.gz" $BIN_HOME
  rm hubble-darwin-${ARCH}.tar*
fi
hubble --version

### Cluster
# Create Kind cluster from config
echo
echo "Creating Kind cluster..."
kind create cluster --config "${__root}/manifests/cluster_config_v1alpha4.yaml"
# Label worker nodes (note - you cannot label them during the creation)
kubectl label --overwrite nodes --selector='!node-role.kubernetes.io/control-plane' 'node-role.kubernetes.io/worker='

# Install Cilium to the cluster
echo
echo "Installing Cilium to the cluster..."
cilium install


### Enable Hubble Observability
# https://docs.cilium.io/en/latest/gettingstarted/hubble_setup/#hubble-setup
if [ -z "${SKIP_HUBBLE:-}" ]; then
  echo
  echo "Enabling Hubble..."
  cilium hubble enable
  cilium status
#  cilium hubble port-forward&
#  hubble status

  echo "Enabling Hubble UI..."
  # Workaround "Unable to enable Hubble: services "hubble-peer" already exists" error
  kubectl delete svc -n kube-system  hubble-peer
  cilium hubble enable --ui

  echo
  echo "To access Hubble UI run: cilium hubble ui"
  echo
fi

kubectl create -f https://raw.githubusercontent.com/cilium/cilium/1.13.0/examples/minikube/http-sw-app.yaml

echo "Done!"
