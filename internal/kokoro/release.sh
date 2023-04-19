#!/bin/bash

# Fail on any error.
set -e

cd github/google-cloud-go/

# Create a directory for storing all the artifacts 
mkdir pkg

# Test prechecks
if [[ -z "${AUTORELEASE_PR:-}" ]]; then
  echo "AUTORELEASE_PR not set. Exiting"
  exit 1
fi

# Extract the PR number from the AUTORELEASE_PR variable
PR_NUMBER=$(echo $AUTORELEASE_PR | awk -v RS='/' 'END{print}')

# Get the list of products released in the PR. 
array=($(curl -L -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
 https://api.github.com/repos/googleapis/google-cloud-go/pulls/$PR_NUMBER/files | \
 jq -r 'map(select(.filename == ".release-please-manifest-individual.json" or .filename == ".release-please-manifest-submodules.json") | .patch)[0]' | \
 awk -v RS='\n' '/^[+]/{print substr($2,2, length($2)-3)}'))

echo ${array[@]}
# For each products create a zip of released versions and store it in pkg 
# directory to be picked up as an artifact by the kokoro job
for element in "${array[@]}"
do
    zip -r "pkg/$element.zip" $element
done

# Store the commit hash in a txt as an artifact.
echo -e $KOKORO_GITHUB_COMMIT >> pkg/commit.txt
