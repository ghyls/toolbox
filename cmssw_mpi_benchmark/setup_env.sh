#! /bin/bash



CMSSW_VER=CMSSW_16_0_0_pre3

THIS_DIR=$(pwd)

source /cvmfs/cms.cern.ch/cmsset_default.sh
cd /shared/$CMSSW_VER/src
# cd /scratch/$CMSSW_VER/src
cmsenv

cd $THIS_DIR
