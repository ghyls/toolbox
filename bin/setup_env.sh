#! /bin/bash

# get CMSSW_BASE from a file in this directory named "cmssw_basedir"
if [ ! -f cmssw_basedir ]; then
    echo "Please create a file named 'cmssw_basedir' in toolbox/bin/ containing the path to use as 'CMSSW_BASE', e.g. '/path/to/CMSSW_16_0_0_pre3/'."
    exit 1
fi


CMSSW_BASE=$(cat cmssw_basedir)

if [ ! -d $CMSSW_BASE ]; then
    echo "The CMSSW_BASE directory '$CMSSW_BASE' does not exist. Please check the path in 'toolbox/bin/cmssw_basedir'."
    exit 1
fi

THIS_DIR=$(pwd)

source /cvmfs/cms.cern.ch/cmsset_default.sh
cd $CMSSW_BASE/src
cmsenv

cd $THIS_DIR
