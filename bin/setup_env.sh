#! /bin/bash

# path/to/CMSSW_X_Y_Z/
CMSSW_BASE=

if [ -z "$CMSSW_BASE" ]; then
    echo "Please open toolbox/bin/setup_env.sh and set the CMSSW_BASE variable to your CMSSW base path."
    exit 1
fi

THIS_DIR=$(pwd)

source /cvmfs/cms.cern.ch/cmsset_default.sh
cd $CMSSW_BASE/src
cmsenv

cd $THIS_DIR
