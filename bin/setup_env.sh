#! /bin/bash

this_script_dir=$(dirname "${BASH_SOURCE[0]}")

path_to_cmssw_basedir="$this_script_dir/cmssw_basedir"
if [ ! -f $path_to_cmssw_basedir ]; then
    echo "Please create a file named 'cmssw_basedir' in $this_script_dir containing the path to use as 'CMSSW_BASE', e.g. '/path/to/CMSSW_16_0_0_pre3/'."
    exit 1
fi


CMSSW_BASE=$(cat $path_to_cmssw_basedir)

if [ ! -d $CMSSW_BASE ]; then
    echo "The CMSSW_BASE directory '$CMSSW_BASE' does not exist. Please check the path in $path_to_cmssw_basedir."
    exit 1
fi

THIS_DIR=$(pwd)

source /cvmfs/cms.cern.ch/cmsset_default.sh
cd $CMSSW_BASE/src
cmsenv

cd $THIS_DIR
