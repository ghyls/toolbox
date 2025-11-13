#!/bin/sh
set -x
POD_NAME=$1
shift
/opt/kube/kubectl exec ${POD_NAME} -- /bin/sh -c "source /cvmfs/cms.cern.ch/el9_amd64_gcc13/external/openmpi/5.0.8-3643ebc674e0ca99382e80cb177a86e4/etc/profile.d/init.sh; $*"
