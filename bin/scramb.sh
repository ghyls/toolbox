set -e

#
# runs scram b -j in a directory relative to $CMSSW_BASE/src
# Usage: scramb.sh [path_from_src]
#

path_from_src="$1"

if [ -z "$CMSSW_BASE" ]; then
  echo "Error: CMSSW_BASE is not set. Do cmsenv first?"
  exit 1
fi

if [ -z "$path_from_src" ]; then
  path_from_src=""
fi

this_dir=$(dirname "$0")    

cd $CMSSW_BASE/src/$path_from_src
scram b -j

cd $this_dir




