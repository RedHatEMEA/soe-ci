#!/bin/bash 

# Push RPMs to satellite
#
# e.g. ${WORKSPACE}/scripts/rpmpush.sh ${WORKSPACE}/soe/artefacts/
#
. ${WORKSPACE}/scripts/common.sh

if [[ -z "$1" ]] || [[ ! -d "$1" ]]
then
    echo "Usage: $0 <artefacts directory>"
    exit ${NOARGS}
fi
workdir=$1

if [[ -z ${PUSH_USER} ]] || [[ -z ${SATELLITE} ]]
then
    echo "PUSH_USER or SATELLITE not set or not found"
    exit ${WORKSPACE_ERR}
fi

# remove any non-rpm files, as they will confuse hammer if we try to sync them
find . -type f -a ! -name '*.rpm' -exec rm {} \;

# We delete extraneous RPMs on the satellite so that we don't keep pushing the same RPMs into the repo
rsync --delete -va -e "ssh -l ${PUSH_USER} -i /var/lib/jenkins/.ssh/id_rsa" -va \
    ${workdir}/rpms/ ${SATELLITE}:rpms
    
# use hammer on the satellite to push the RPMs into the repo
# the ID of the ACME Test repository is 16
ssh -l ${PUSH_USER} -i /var/lib/jenkins/.ssh/id_rsa ${SATELLITE} \
    "hammer repository upload-content --id ${REPO_ID} --path ./rpms"


