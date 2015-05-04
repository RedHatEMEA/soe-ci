#!/bin/bash -x

# Push BATS tests to test VMs
#
# e.g ${WORKSPACE}/scripts/pushtests.sh 'test'
#

# Load common parameter variables
. $(dirname "${0}")/common.sh

# get our test machines
J=0
for I in $(ssh -l ${PUSH_USER} -i ${RSA_ID} ${SATELLITE} \
        "hammer content-host list --organization \"${ORG}\" --host-collection \"$TESTVM_HOSTCOLLECTION\" \
            | tail -n +4 | cut -f2 -d \"|\" | head -n 1")
do
  vm[$J]=$I
  ((J+=1))
done

# we need to wait until all the test machines have been rebuilt by foreman
REBUILT=0
WAIT=0
while [[ ${REBUILT} -lt ${#vm[@]} ]]
    do
    sleep 10
    ((WAIT+=10))
    echo "Waiting 10 seconds"
    for I in ${vm[@]}
    do
        echo -n "Checking if test server $I has rebuilt..."
        status=$(ssh -l ${PUSH_USER} -i ${RSA_ID} ${SATELLITE} \
            "hammer host info --name $I | \
            grep -e \"Managed.*true\" -e \"Enabled.*true\" -e \"Build.*false\" | wc -l")
        if [[ ${status} == 3 ]]
        then
            echo "Success!"
            ((REBUILT+=1))
        else
            echo "Not yet"
        fi
    done
    if [[ ${WAIT} -gt 6000 ]]
    then
        echo "Test servers still not rebuilt after 6000 seconds. Exiting."
        exit 1
    fi
done

# Wait another 60s to be on the safe side
sleep 60

# copy our tests to the test servers
export SSH_ASKPASS=${WORKSPACE}/scripts/askpass.sh
export DISPLAY=nodisplay
export TEST_ROOT
for I in ${vm[@]}
do
    echo "Setting up ssh keys for test server $I"
    sed -i.bak "s/^$I.*//" ${KNOWN_HOSTS}
    if ! ssh-copy-id -o StrictHostKeyChecking=no -i ${RSA_ID} root@$I
    then # RHEL 6's ssh-copy-id doesn't support -o
        ssh-copy-id -i ${RSA_ID} root@$I
    fi

    echo "Installing bats and rsync on test server $I"
    ssh -o StrictHostKeyChecking=no -i ${RSA_ID} root@$I "yum install -y bats rsync"    
    echo "copying tests to test server $I"
    rsync --delete -va -e "ssh -o StrictHostKeyChecking=no -i ${RSA_ID}" ${WORKSPACE}/soe/tests \
        root@$I:
done

# execute the tests in parallel on all test servers
mkdir -p ${WORKSPACE}/test_results
for I in ${vm[@]}
do
    echo "Starting TAPS tests on test server $I"
    ssh -o StrictHostKeyChecking=no -i ${RSA_ID} root@$I \
        'cd tests ; bats -t *.bats' > ${WORKSPACE}/test_results/$I.tap &
done

# wait until all backgrounded processes have exited
wait
