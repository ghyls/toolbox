#!/bin/sh
#set -x
POD_NAME=$1

TOOLBOX_DIR=$(cd "$(dirname "$0")/.." && pwd)

shift
/opt/kube/kubectl exec ${POD_NAME} -- /bin/sh -c "source ${TOOLBOX_DIR}/bin/setup_env.sh; $*"