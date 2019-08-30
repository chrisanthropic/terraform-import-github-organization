#!/bin/bash
set -euo pipefail

# debug mode
set -x

# ENVIRONMENTAL VARIABLES
GITHUB_TOKEN=${GITHUB_TOKEN:-''}
ORG=${ORG:-''}
API_URL_PREFIX=${API_URL_PREFIX:-'https://api.github.com'}

# FUNCTIONS

# Public Repos
  # You can only list 100 items per page, so you can only clone 100 at a time.
  # This function uses the API to calculate how many pages of public repos you have.
get_public_pagination () {
    public_pages=$(curl -I "${API_URL_PREFIX}/orgs/${ORG}/repos?access_token=${GITHUB_TOKEN}&per_page=100" | grep -Eo '&page=[0-9]+' | grep -Eo '[0-9]+' | tail -1;)
    echo "${public_pages:-1}"
}
  # This function uses the output from above and creates an array counting from 1->$ 
limit_public_pagination () {
  seq "$(get_public_pagination)"
}

  # Now lets import the repos, starting with page 1 and iterating through the pages
import_public_repos () {
  for PAGE in $(limit_public_pagination); do
  
    for i in $(curl -s "${API_URL_PREFIX}/orgs/${ORG}/repos?access_token=${GITHUB_TOKEN}&page=${PAGE}&per_page=100&sort=full_name" | jq -r 'sort_by(.name) | .[] | .name'); do
      
      #avoid abusing the github api and reread the file from memory cache
      PUBLIC_REPO_PAYLOAD=$(curl -s "${API_URL_PREFIX}/repos/${ORG}/${i}?access_token=${GITHUB_TOKEN}&" -H "Accept: application/vnd.github.mercy-preview+json")
      PUBLIC_REPO_DESCRIPTION=$(echo "$PUBLIC_REPO_PAYLOAD" | jq -r '.description | select(type == "string")' | sed "s/\"/'/g")
      PUBLIC_REPO_DOWNLOADS=$(echo "$PUBLIC_REPO_PAYLOAD" | jq -r .has_downloads)
      PUBLIC_REPO_WIKI=$(echo "$PUBLIC_REPO_PAYLOAD" | jq -r .has_wiki)
      PUBLIC_REPO_ISSUES=$(echo "$PUBLIC_REPO_PAYLOAD" | jq -r .has_issues)
      PUBLIC_REPO_ARCHIVED=$(echo "$PUBLIC_REPO_PAYLOAD" | jq -r .archived)
      PUBLIC_REPO_TOPICS=$(echo "$PUBLIC_REPO_PAYLOAD" | jq -r .topics)
      PUBLIC_REPO_PROJECTS=$(echo "$PUBLIC_REPO_PAYLOAD" | jq -r .has_projects)
      PUBLIC_REPO_MERGE_COMMIT=$(echo "$PUBLIC_REPO_PAYLOAD" | jq -r .allow_merge_commit)
      PUBLIC_REPO_REBASE_MERGE=$(echo "$PUBLIC_REPO_PAYLOAD" | jq -r .allow_rebase_merge)
      PUBLIC_REPO_SQUASH_MERGE=$(echo "$PUBLIC_REPO_PAYLOAD" | jq -r .allow_squash_merge)
      PUBLIC_REPO_AUTO_INIT=$(echo "$PUBLIC_REPO_PAYLOAD" | jq -r '.auto_init == true')
      PUBLIC_REPO_DEFAULT_BRANCH=$(echo "$PUBLIC_REPO_PAYLOAD" | jq -r .default_branch)
      PUBLIC_REPO_GITIGNORE_TEMPLATE=$(echo "$PUBLIC_REPO_PAYLOAD" | jq -r .gitignore_template)
      PUBLIC_REPO_LICENSE_TEMPLATE=$(echo "$PUBLIC_REPO_PAYLOAD" | jq -r '.license_template | select(type == "string")')
      PUBLIC_REPO_HOMEPAGE_URL=$(echo "$PUBLIC_REPO_PAYLOAD" | jq -r '.homepage | select(type == "string")')
     
      # Terraform doesn't like '.' in resource names, so if one exists then replace it with a dash
      TERRAFORM_PUBLIC_REPO_NAME=$(echo "${i}" | tr  "."  "-")
      import_repos_protected_branches

      cat >> github-public-repos.tf << EOF
resource "github_repository" "${TERRAFORM_PUBLIC_REPO_NAME}" {
  name               = "${i}"
  topics             = ${PUBLIC_REPO_TOPICS}
  description        = "${PUBLIC_REPO_DESCRIPTION}"
  private            = false
  has_wiki           = ${PUBLIC_REPO_WIKI}
  has_projects       = ${PUBLIC_REPO_PROJECTS}
  has_downloads      = ${PUBLIC_REPO_DOWNLOADS}
  has_issues         = ${PUBLIC_REPO_ISSUES}
  archived           = ${PUBLIC_REPO_ARCHIVED}
  allow_merge_commit = ${PUBLIC_REPO_MERGE_COMMIT}
  allow_rebase_merge = ${PUBLIC_REPO_REBASE_MERGE}
  allow_squash_merge = ${PUBLIC_REPO_SQUASH_MERGE}
  auto_init          = ${PUBLIC_REPO_AUTO_INIT}
  gitignore_template = ${PUBLIC_REPO_GITIGNORE_TEMPLATE}
  license_template   = "${PUBLIC_REPO_LICENSE_TEMPLATE}"
  homepage_url       = "${PUBLIC_REPO_HOMEPAGE_URL}"
}
EOF

      # Import the Repo
      terraform import "github_repository.${TERRAFORM_PUBLIC_REPO_NAME}" "${i}"
    done
  done
echo "~~~Completed with Public Repos~~~"  
}

import_repos_protected_branches () {
# debug
#set -x

      PROTECTION_BRANCH_PAYLOAD=$(curl -s "${API_URL_PREFIX}/repos/${ORG}/${PROTECTED_BRANCH}/branches?access_token=${GITHUB_TOKEN}&" -H "Accept: application/vnd.github.mercy-preview+json")

      PUBLIC_REPO_DOWNLOADS=$(echo "$PUBLIC_REPO_PAYLOAD" | jq -r .has_downloads)
      PUBLIC_REPO_WIKI=$(echo "$PUBLIC_REPO_PAYLOAD" | jq -r .has_wiki)
      PROTECTED_BRANCH_REQUIRED_PULL_REQUEST_REVIEWS_TEAMS=$(echo "$PUBLIC_REPO_PAYLOAD" | jq -r '.required_pull_request_reviews.team[]?.slug')
      PROTECTED_BRANCH_RESTRICTIONS_USERS=$(echo "$PUBLIC_REPO_PAYLOAD" | jq -r '.restrictions.users[]?.login')

      # convert bash arrays into csv list


      # write to terraform file
      cat >> github-public-repos.tf << EOF
resource "github_branch_protection" "${i}" {
  repository     = "${i}"
  branch         = "${protected_branch}"
  enforce_admins = ${PROTECTED_BRANCH_ENFORCE_ADMINS}

  required_status_checks {
    strict   = ${PROTECTED_BRANCH_REQUIRED_STATUS_CHECKS_STRICT}
    contexts = ${PROTECTED_BRANCH_REQUIRED_STATUS_CHECKS_CONTEXTS}
  }

  required_pull_request_reviews {
    dismiss_stale_reviews = true
    dismissal_users       = ["${PROTECTED_BRANCH_REQUIRED_PULL_REQUEST_REVIEWS_USERS_LIST}"]
    dismissal_teams       = ["${PROTECTED_BRANCH_REQUIRED_PULL_REQUEST_REVIEWS_TEAMS_LIST}"]
  }

  restrictions {
    users = ["${PROTECTED_BRANCH_RESTRICTIONS_USERS_LIST}"]
    teams = ["${PROTECTED_BRANCH_RESTRICTIONS_TEAMS_LIST}"]
  }
}
EOF

      # terraform import github_repository
      #terraform import "github_repository.${i}" "${i}"
      # Import the Protected Branch
      #terraform import "github_branch_protection.${protected_branch}" "${i}" 
  done
}

# for testing public_repos and protected_branchs functions only uncomment
#import_public_repos
#exit 0

# Private Repos
get_private_pagination () {
    priv_pages=$(curl -I "${API_URL_PREFIX}/orgs/${ORG}/repos?access_token=${GITHUB_TOKEN}&type=private&per_page=100" | grep -Eo '&page=[0-9]+' | grep -Eo '[0-9]+' | tail -1;)
    echo "${priv_pages:-1}"
}

limit_private_pagination () {
  seq "$(get_private_pagination)"
}

import_private_repos () {
  for PAGE in $(limit_private_pagination); do

    for i in $(curl -s "${API_URL_PREFIX}/orgs/${ORG}/repos?access_token=${GITHUB_TOKEN}&type=private&page=${PAGE}&per_page=100" | jq -r 'sort_by(.name) | .[] | .name'); do

      #avoid abusing the github api and reread the file from memory cache
      PRIVATE_REPO_PAYLOAD=$(curl -s "${API_URL_PREFIX}/repos/${ORG}/${i}?access_token=${GITHUB_TOKEN}" -H "Accept: application/vnd.github.mercy-preview+json")

      PRIVATE_REPO_DESCRIPTION=$(echo "$PRIVATE_REPO_PAYLOAD" | jq -r '.description | select(type == "string")' | sed "s/\"/'/g")
      PRIVATE_REPO_DOWNLOADS=$(echo "$PRIVATE_REPO_PAYLOAD" | jq -r .has_downloads)
      PRIVATE_REPO_WIKI=$(echo "$PRIVATE_REPO_PAYLOAD" | jq -r .has_wiki)
      PRIVATE_REPO_ISSUES=$(echo "$PRIVATE_REPO_PAYLOAD" | jq -r .has_issues)
      PRIVATE_REPO_ARCHIVED=$(echo "$PRIVATE_REPO_PAYLOAD" | jq -r .archived)
      PRIVATE_REPO_TOPICS=$(echo "$PRIVATE_REPO_PAYLOAD" | jq -r .topics)
      PRIVATE_REPO_PROJECTS=$(echo "$PRIVATE_REPO_PAYLOAD" | jq -r .has_projects)
      PRIVATE_REPO_MERGE_COMMIT=$(echo "$PRIVATE_REPO_PAYLOAD" | jq -r .allow_merge_commit)
      PRIVATE_REPO_REBASE_MERGE=$(echo "$PRIVATE_REPO_PAYLOAD" | jq -r .allow_rebase_merge)
      PRIVATE_REPO_SQUASH_MERGE=$(echo "$PRIVATE_REPO_PAYLOAD" | jq -r .allow_squash_merge)
      PRIVATE_REPO_AUTO_INIT=$(echo "$PRIVATE_REPO_PAYLOAD" | jq -r .auto_init)
      PRIVATE_REPO_DEFAULT_BRANCH=$(echo "$PRIVATE_REPO_PAYLOAD" | jq -r .default_branch)
      PRIVATE_REPO_GITIGNORE_TEMPLATE=$(echo "$PRIVATE_REPO_PAYLOAD" | jq -r .gitignore_template)
      PRIVATE_REPO_LICENSE_TEMPLATE=$(echo "$PRIVATE_REPO_PAYLOAD" | jq -r '.license_template | select(type == "string")')
      PRIVATE_REPO_HOMEPAGE_URL=$(echo "$PRIVATE_REPO_PAYLOAD" | jq -r '.homepage | select(type == "string")')
     
      # Terraform doesn't like '.' in resource names, so if one exists then replace it with a dash
      TERRAFORM_PRIVATE_REPO_NAME=$(echo "${i}" | tr  "."  "-")

      cat >> github-private-repos.tf << EOF
resource "github_repository" "${TERRAFORM_PRIVATE_REPO_NAME}" {
  name               = "${i}"
  private            = true
  description        = "${PRIVATE_REPO_DESCRIPTION}"
  has_wiki           = ${PRIVATE_REPO_WIKI}
  has_projects       = ${PRIVATE_REPO_PROJECTS}
  has_downloads      = ${PRIVATE_REPO_DOWNLOADS}
  has_issues         = ${PRIVATE_REPO_ISSUES}
  archived           = ${PRIVATE_REPO_ARCHIVED}
  topics             = ${PRIVATE_REPO_TOPICS}
  allow_merge_commit = ${PRIVATE_REPO_MERGE_COMMIT}
  allow_rebase_merge = ${PRIVATE_REPO_REBASE_MERGE}
  allow_squash_merge = ${PRIVATE_REPO_SQUASH_MERGE}
  auto_init          = ${PRIVATE_REPO_AUTO_INIT}
  gitignore_template = ${PRIVATE_REPO_GITIGNORE_TEMPLATE}
  license_template   = "${PRIVATE_REPO_LICENSE_TEMPLATE}"
  homepage_url       = "${PRIVATE_REPO_HOMEPAGE_URL}"
}

EOF
      # Import the Repo
      terraform import "github_repository.${TERRAFORM_PRIVATE_REPO_NAME}" "${i}"
    done
  done
}

# Users
import_users () {
  for i in $(curl -s "${API_URL_PREFIX}/orgs/${ORG}/members?access_token=${GITHUB_TOKEN}&per_page=100" | jq -r 'sort_by(.login) | .[] | .login'); do

  cat >> github-users.tf << EOF
resource "github_membership" "${i}" {
  username        = "${i}"
  role            = "member"
}
EOF
    terraform import "github_membership.${i}" "${ORG}:${i}"
  done
}

# Teams
import_teams () {
  for i in $(curl -s "${API_URL_PREFIX}/orgs/${ORG}/teams?access_token=${GITHUB_TOKEN}&per_page=100" -H "Accept: application/vnd.github.hellcat-preview+json" | jq -r 'sort_by(.name) | .[] | .id'); do
  
    TEAM_NAME=$(curl -s "${API_URL_PREFIX}/teams/${i}?access_token=${GITHUB_TOKEN}&per_page=100" -H "Accept: application/vnd.github.hellcat-preview+json" | jq -r .name)
    TEAM_NAME_NO_SPACE=`echo $TEAM_NAME | tr " " "_"`

    TEAM_PRIVACY=$(curl -s "${API_URL_PREFIX}/teams/${i}?access_token=${GITHUB_TOKEN}&per_page=100" -H "Accept: application/vnd.github.hellcat-preview+json" | jq -r .privacy)
  
    TEAM_DESCRIPTION=$(curl -s "${API_URL_PREFIX}/teams/${i}?access_token=${GITHUB_TOKEN}&per_page=100" -H "Accept: application/vnd.github.hellcat-preview+json" | jq -r .description)
  
    if [[ "${TEAM_PRIVACY}" == "closed" ]]; then
      cat >> "github-teams.tf" << EOF
resource "github_team" "${TEAM_NAME_NO_SPACE}" {
  name        = "${TEAM_NAME}"
  description = "${TEAM_DESCRIPTION}"
  privacy     = "closed"
}
EOF
    elif [[ "${TEAM_PRIVACY}" == "secret" ]]; then
      cat >> "github-teams.tf" << EOF
resource "github_team" "${TEAM_NAME_NO_SPACE}" {
  name        = "${TEAM_NAME}"
  description = "${TEAM_DESCRIPTION}"
  privacy     = "secret"
}
EOF
    fi

    terraform import "github_team.${TEAM_NAME_NO_SPACE}" "${i}"
  done
}

# Team Memberships 
import_team_memberships () {
  for i in $(curl -s "${API_URL_PREFIX}/orgs/${ORG}/teams?access_token=${GITHUB_TOKEN}&per_page=100" -H "Accept: application/vnd.github.hellcat-preview+json" | jq -r 'sort_by(.name) | .[] | .id'); do
  
  TEAM_NAME=$(curl -s "${API_URL_PREFIX}/teams/${i}?access_token=${GITHUB_TOKEN}&per_page=100" -H "Accept: application/vnd.github.hellcat-preview+json" | jq -r .name | tr " " "_")
  
    for j in $(curl -s "${API_URL_PREFIX}/teams/${i}/members?access_token=${GITHUB_TOKEN}&per_page=100" -H "Accept: application/vnd.github.hellcat-preview+json" | jq -r .[].login); do
    
      TEAM_ROLE=$(curl -s "${API_URL_PREFIX}/teams/${i}/memberships/${j}?access_token=${GITHUB_TOKEN}&per_page=100" -H "Accept: application/vnd.github.hellcat-preview+json" | jq -r .role)

      if [[ "${TEAM_ROLE}" == "maintainer" ]]; then
        cat >> "github-team-memberships.tf" << EOF
resource "github_team_membership" "${TEAM_NAME}-${j}" {
  username    = "${j}"
  team_id     = "\${github_team.${TEAM_NAME}.id}"
  role        = "maintainer"
}
EOF
      elif [[ "${TEAM_ROLE}" == "member" ]]; then
        cat >> "github-team-memberships.tf" << EOF
resource "github_team_membership" "${TEAM_NAME}-${j}" {
  username    = "${j}"
  team_id     = "\${github_team.${TEAM_NAME}.id}"
  role        = "member"
}
EOF
      fi
      terraform import "github_team_membership.${TEAM_NAME}-${j}" "${i}:${j}"
    done
  done
}

get_team_pagination () {
    team_pages=$(curl -I "${API_URL_PREFIX}/orgs/${ORG}/repos?access_token=${GITHUB_TOKEN}&per_page=100" | grep -Eo '&page=\d+' | grep -Eo '[0-9]+' | tail -1;)
    echo "${team_pages:-1}"
}
  # This function uses the out from above and creates an array counting from 1->$ 
limit_team_pagination () {
  seq "$(get_team_pagination)"
}

get_team_ids () {
  curl -s "${API_URL_PREFIX}/orgs/${ORG}/teams?access_token=${GITHUB_TOKEN}&per_page=100" -H "Accept: application/vnd.github.hellcat-preview+json" | jq -r 'sort_by(.name) | .[] | .id'
}

get_team_repos () {
  for PAGE in $(limit_team_pagination); do

    for i in $(curl -s "${API_URL_PREFIX}/teams/${TEAM_ID}/repos?access_token=${GITHUB_TOKEN}&page=${PAGE}&per_page=100" | jq -r 'sort_by(.name) | .[] | .name'); do
    
    TERRAFORM_TEAM_REPO_NAME=$(echo "${i}" | tr  "."  "-")
    TEAM_NAME=$(curl -s "${API_URL_PREFIX}/teams/${TEAM_ID}?access_token=${GITHUB_TOKEN}" | jq -r .name | tr " " "_")

    ADMIN_PERMS=$(curl -s "${API_URL_PREFIX}/teams/${TEAM_ID}/repos/${ORG}/${i}?access_token=${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3.repository+json" | jq -r .permissions.admin )
    PUSH_PERMS=$(curl -s "${API_URL_PREFIX}/teams/${TEAM_ID}/repos/${ORG}/${i}?access_token=${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3.repository+json" | jq -r .permissions.push )
    PULL_PERMS=$(curl -s "${API_URL_PREFIX}/teams/${TEAM_ID}/repos/${ORG}/${i}?access_token=${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3.repository+json" | jq -r .permissions.pull )
  
    if [[ "${ADMIN_PERMS}" == "true" ]]; then
      cat >> "github-teams.tf" << EOF
resource "github_team_repository" "${TEAM_NAME}-${TERRAFORM_TEAM_REPO_NAME}" {
  team_id    = "${TEAM_ID}"
  repository = "${i}"
  permission = "admin"
}

EOF
    elif [[ "${PUSH_PERMS}" == "true" ]]; then
      cat >> "github-teams.tf" << EOF
resource "github_team_repository" "${TEAM_NAME}-${TERRAFORM_TEAM_REPO_NAME}" {
  team_id    = "${TEAM_ID}"
  repository = "${i}"
  permission = "push"
}

EOF
    elif [[ "${PULL_PERMS}" == "true" ]]; then
      cat >> "github-teams.tf" << EOF
resource "github_team_repository" "${TEAM_NAME}-${TERRAFORM_TEAM_REPO_NAME}" {
  team_id    = "${TEAM_ID}"
  repository = "${i}"
  permission = "pull"
}

EOF
    fi
    terraform import "github_team_repository.${TEAM_NAME}-${TERRAFORM_TEAM_REPO_NAME}" "${TEAM_ID}:${i}"
    done
  done
}

import_team_repos () {
for TEAM_ID in $(get_team_ids); do
  get_team_repos
done
}

import_all_team_resources () {
  import_teams
  import_team_memberships
  import_team_repos
}

###
## DO IT YO
###
import_public_repos
#import_repos_protected_branches
# to test set the vars that you need here and then call the function so you can. 
import_private_repos
import_users
import_all_team_resources
