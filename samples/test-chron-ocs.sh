#!/bin/bash

set -e

retry_ocp_arg=
get_latest_ocs=false
nargs=$#
i=1
while (( $i<=$nargs ))
do
	arg=$1
	case "$arg" in
	--retry-ocp)
		retry_ocp_arg=--retry
		shift 1
		;;
	--latest-ocs)
		get_latest_ocs=true
		shift 1
		;;
	*)
		echo "Usage: $0 [ --retry-ocp ] [ --latest-ocs ]"
		echo ""
		echo "Use --retry when an error occurs while creating the ocp cluster."
		echo "In this case, the existing VMs are reused and terraform is re-invoked."
		echo "The default behaviour is to destroy the existing cluster."
		echo ""
		echo "Use --latest-ocs to pull the latest commit from the ocsi-ci GH repo"
		exit 1
	esac
	(( i++ ))
done

# Edit username and password below or better specify them via the command line

if [ -z "$RHID_USERNAME" ]; then
	export RHID_USERNAME=
fi
if [ -z "$RHID_PASSWORD" ]; then
	export RHID_PASSWORD=
fi

set -x

#export OCP_VERSION=4.6 			# 4.5 is default.  4.4 and 4.6 also supported

#export WORKERS=5				# Default is 3 

# This image is obtained from RedHat Customer Portal and must be prepared for use

#export BASTION_IMAGE=${BASTION_IMAGE:="rhel-8.2-update-2-ppc64le-kvm.qcow2"}

# Controls file placement of VM boot images.  Set to fs with the most space

#export IMAGES_PATH=/var/lib/libvirt/images

# To use disk partitions for VM data disks, set DATA_DISK_LIST to partition names
# To use files instead, unset DATA_DISK_LIST

#if [ -z "$DATA_DISK_LIST" ]; then
#	export DATA_DISK_LIST="sdc1,sdd1,sde1"	# Each worker requires a unique partition
#fi

#export FORCE_DISK_PARTITION_WIPE=true		# Default is false

set +x

# Set WORKSPACE where go code, binaries, and log files are placed

if [ -z "$WORKSPACE" ]; then
	cwdir=$(pwd)
	cmdpath=$(dirname $0)
	if [[ "$cmdpath" =~ "ocs-upi-kvm/samples" ]]; then
		if [[ "$cmdpath" =~ ^/ ]]; then
			export WORKSPACE=$cmdpath/../..
		else
			export WORKSPACE=$cwdir/$cmdpath/../..
		fi
	elif [[ "$cmdpath" =~ "samples" ]]; then
		export WORKSPACE=$cwdir/..
	elif [ -d ocs-upi-kvm ]; then
		export WORKSPACE=$cwdir
	else
		echo "Could not find ocs-upi-kvm directory"
		exit 1
	fi
fi

echo "Location of project: $WORKSPACE/ocs-upi-kvm"
echo "Location of log files: $WORKSPACE"

pushd $WORKSPACE/ocs-upi-kvm
if [ ! -e src/ocp4-upi-kvm/var.tfvars ]; then
	echo "Refreshing submodule ocp4-upi-kvm..."
	git submodule update --init src/ocp4-upi-kvm
fi

if [ ! -e src/ocs-ci/README.md ]; then
	echo "Refreshing submodule ocs-ci..."
	git submodule update --init src/ocs-ci
fi

if [ "$get_latest_ocs" == true ]; then
	echo "Getting latest ocs-ci..."
	pushd $WORKSPACE/ocs-upi-kvm/src/ocs-ci
	git checkout master
	git pull
	popd
fi

export RHID_USERNAME=<your rhid username>
export RHID_PASSWORD=<your rhid password>
export OCP_VERSION=4.5
export IMAGES_PATH=/home/libvirt/images

echo "Invoking scripts..."

pushd $WORKSPACE/ocs-upi-kvm/scripts

set -o pipefail

./create-ocp.sh $retry_ocp_arg 2>&1 | tee $LOGDIR/create-ocp-$LOGDDATE.log

source $WORKSPACE/env-ocp.sh
oc get nodes -o wide 2>&1 | tee -a $LOGDIR/create-ocp-$LOGDATE.log

./setup-ocs-ci.sh 2>&1 | tee $LOGDIR/setup-ocs-ci-$LOGDATE.log
./deploy-ocs-ci.sh 2>&1 | tee $LOGDIR/deploy-ocs-ci-$LOGDATE.log

./test-ocs-ci.sh --tier 2,3,4,4a,4b,4c > $LOGDIR/test-ocs-ci-$LOGDATE.log
