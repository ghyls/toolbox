#!/bin/sh
set -x
POD_NAME=$2
shift
/opt/kube/kubectl exec ${POD_NAME} -- /bin/sh -c "
    source ~/ngt-farm/scripts/setup_env.sh &&
    exec $2 $3 $4 $5 $6 $7 $8 $9 ${10} ${11} ${12} ${13} ${14} ${15} ${16} ${17} ${18} ${19} ${20} ${21} ${22} ${23} ${24} ${25} ${26}"
