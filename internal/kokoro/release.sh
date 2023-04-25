#!/bin/bash

# Fail on any error.
set -eo pipefail

# Always run the cleanup script, regardless of the success of bouncing into
# the container.
function cleanup() {
  rm -rf "${KOKORO_GFILE_DIR}"
  echo "cleanup";
}
trap cleanup EXIT

$(dirname $0)/populate-secrets.sh # Secret Manager secrets.

# Start the releasetool reporter
requirementsFile=$(realpath $(dirname "$0"))/requirements.txt
python3 -m pip install --require-hashes -r $requirementsFile
python3 -m releasetool publish-reporter-script > /tmp/publisher-script; source /tmp/publisher-script

cd github/google-cloud-go/

# Create a directory for storing all the artifacts 
mkdir pkg

# Test prechecks
if [ -z "${AUTORELEASE_PR}" ]
then
  echo "Need to provide URL to release PR via AUTORELEASE_PR environment variable"
  exit 1
fi

# Extract the PR number from the AUTORELEASE_PR variable
get_pr_number () {
  echo $(echo $1 | awk -v RS='/' 'END{print}')
}

# Get the PR number 
pr_number=$(get_pr_number $AUTORELEASE_PR)

# Returns the list of modules released in the PR. 
release_modules () {
  pr_diff=$(curl https://api.github.com/repos/googleapis/google-cloud-go/pulls/$1/files)
  echo $(jq -r 'map(select(.filename == ".release-please-manifest-individual.json" or .filename == ".release-please-manifest-submodules.json") | .patch)[0]' <<< $pr_diff | \
         awk -v RS='\n' '/^[+]/{print substr($2,2, length($2)-3)}')
}

# Get the list of released modules
release_modules_list=($(release_modules $pr_number))

# For each module create a zip of released versions and store it in pkg 
# directory to be picked up as an artifact by the kokoro job
for module in "${release_modules_list[@]}"
do
    zip -r "pkg/$module.zip" $module
done

# Store the commit hash in a txt as an artifact.
echo -e $KOKORO_GITHUB_COMMIT >> pkg/commit.txt

# Test!
sample_pr_1="https://github.com/googleapis/google-cloud-go/pull/7687"
sample_pr_2="https://github.com/googleapis/google-cloud-go/pull/7701"

pr_number_1=$(get_pr_number $sample_pr_1)
pr_number_2=$(get_pr_number $sample_pr_2)

if [ "$pr_number_1" != "7687" ] ; then
  echo "Error: Incorrect value from get_pr_number."
  exit
fi

if [ "$(release_modules $pr_number_1)" != "aiplatform appengine compute contactcenterinsights container iap retail security workstations" ] ; then
  echo "Error: Incorrect value from release_modules."
  exit
fi

if [ "$(release_modules $pr_number_2)" != "bigquery" ] ; then
  echo "Error: Incorrect value from release_modules."
  exit
fi
