

set -e

target_mpi_impl="$1"

if [ -z "$CMSSW_BASE" ]; then
  echo "Error: CMSSW_BASE is not set. Do cmsenv first?"
  exit 1
fi

if [ "$target_mpi_impl" != "mpich" ] && [ "$target_mpi_impl" != "openmpi" ]; then
  echo "Error: target_mpi_impl must be either 'mpich' or 'openmpi'"
  echo "Usage: switch_cmssw_mpi.sh <mpich|openmpi>"
  exit 1
fi

this_dir=$(dirname "$0")

cd $CMSSW_BASE



set +e
scram tool remove openmpi
scram tool remove mpich
set -e

scram setup $target_mpi_impl

mpi_tool_xml="$CMSSW_BASE/config/toolbox/$SCRAM_ARCH/tools/selected/mpi.xml"

sed -i "s/<use name=\"[^\"]*\"\/>/<use name=\"$target_mpi_impl\"\/>/" "$mpi_tool_xml"

cat "$mpi_tool_xml"

scram setup mpi

cd $CMSSW_BASE/src
cmsenv
scram b -j













