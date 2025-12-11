#!/bin/sh
#set -x
POD_NAME=$1
shift
/opt/kube/kubectl exec ${POD_NAME} -- /bin/sh -c "source setup_env.sh; $*"
