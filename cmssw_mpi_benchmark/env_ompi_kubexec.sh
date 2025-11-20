#!/bin/sh
set -x
POD_NAME=$1
shift
/opt/kube/kubectl exec ${POD_NAME} -- /bin/sh -c "source ~/ngt-farm/scripts/setup_env.sh; $*"
