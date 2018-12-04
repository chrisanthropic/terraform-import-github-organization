#!/bin/bash
# set -euo pipefail

###
## GLOBAL VARIABLES
###
GITHUB_TOKEN=${GITHUB_TOKEN:-''}
ORG=${ORG:-''}
API_URL_PREFIX=${API_URL_PREFIX:-'https://api.github.com'}

###
## FUNCTIONS
###

# Public Repos
  # You can only list 100 items per page, so you can only clone 100 at a time.
  # This function uses the API to calculate how many pages of public repos you have.
get_public_pagination () {
    public_pages=$(curl -I "${API_URL_PREFIX}/orgs/$ORG/repos?access_token=$GITHUB_TOKEN&type=public&per_page=100" | grep -Eo '&page=\d+' | grep -Eo '[0-9]+' | tail -1;)
    echo ${public_pages:-1}
}
  # This function uses the output from above and creates an array counting from 1->$ 
limit_public_pagination () {
  seq $(get_public_pagination)
}

  # Now lets import the repos, starting with page 1 and iterating through the pages
import_public_repos () {
  for PAGE in $(limit_public_pagination); do
  
    for i in $(curl -s "${API_URL_PREFIX}/orgs/$ORG/repos?access_token=$GITHUB_TOKEN&type=public&page=$PAGE&per_page=100" | jq -r 'sort_by(.name) | .[] | .name'); do
  
  
      PUBLIC_REPO_DESCRIPTION=$(curl -s "${API_URL_PREFIX}/repos/$ORG/$i?access_token=$GITHUB_TOKEN" | jq -r .description | sed "s/\"/'/g")
      PUBLIC_REPO_DOWNLOADS=$(curl -s "${API_URL_PREFIX}/repos/$ORG/$i?access_token=$GITHUB_TOKEN" | jq -r .has_downloads)
      
      PUBLIC_REPO_WIKI=$(curl -s "${API_URL_PREFIX}/repos/$ORG/$i?access_token=$GITHUB_TOKEN" | jq -r .has_wiki)
      
      PUBLIC_REPO_ISSUES=$(curl -s "${API_URL_PREFIX}/repos/$ORG/$i?access_token=$GITHUB_TOKEN" | jq -r .has_issues)
     
      # Terraform doesn't like '.' in resource names, so if one exists then replace it with a dash
      TERRAFORM_PUBLIC_REPO_NAME=$(echo $i | tr  "."  "-")

      cat >> github-public-repos.tf << EOF
resource "github_repository" "$TERRAFORM_PUBLIC_REPO_NAME" {
  name        = "$i"
  private     = false
  description = "$PUBLIC_REPO_DESCRIPTION"
  has_wiki    = "$PUBLIC_REPO_WIKI"
  has_downloads = "$PUBLIC_REPO_DOWNLOADS"
  has_issues  = "$PUBLIC_REPO_ISSUES"
}
EOF

      # Import the Repo
      terraform import github_repository.$TERRAFORM_PUBLIC_REPO_NAME $i
    done
  done
}

# Private Repos
get_private_pagination () {
    priv_pages=$(curl -I "${API_URL_PREFIX}/orgs/$ORG/repos?access_token=$GITHUB_TOKEN&type=private&per_page=100" | grep -Eo '&page=\d+' | grep -Eo '[0-9]+' | tail -1;)
    echo ${priv_pages:-1}
}

limit_private_pagination () {
  seq $(get_private_pagination)
}

import_private_repos () {
  for PAGE in $(limit_private_pagination); do

    for i in $(curl -s "${API_URL_PREFIX}/orgs/$ORG/repos?access_token=$GITHUB_TOKEN&type=private&page=$PAGE&per_page=100" | jq -r 'sort_by(.name) | .[] | .name'); do
  
      PRIVATE_REPO_DESCRIPTION=$(curl -s "${API_URL_PREFIX}/repos/$ORG/$i?access_token=$GITHUB_TOKEN" | jq -r .description | sed "s/\"/'/g")
      
      PRIVATE_REPO_DOWNLOADS=$(curl -s "${API_URL_PREFIX}/repos/$ORG/$i?access_token=$GITHUB_TOKEN" | jq -r .has_downloads)
      
      PRIVATE_REPO_WIKI=$(curl -s "${API_URL_PREFIX}/repos/$ORG/$i?access_token=$GITHUB_TOKEN" | jq -r .has_wiki)
      
      PRIVATE_REPO_ISSUES=$(curl -s "${API_URL_PREFIX}/repos/$ORG/$i?access_token=$GITHUB_TOKEN" | jq -r .has_issues)
     
      # Terraform doesn't like '.' in resource names, so if one exists then replace it with a dash
      TERRAFORM_PRIVATE_REPO_NAME=$(echo $i | tr  "."  "-")

      cat >> github-private-repos.tf << EOF
resource "github_repository" "$TERRAFORM_PRIVATE_REPO_NAME" {
  name        = "$i"
  private     = true
  description = "$PRIVATE_REPO_DESCRIPTION"
  has_wiki    = "$PRIVATE_REPO_WIKI"
  has_downloads = "$PRIVATE_REPO_DOWNLOADS"
  has_issues  = "$PRIVATE_REPO_ISSUES"
}

EOF
      # Import the Repo
      terraform import github_repository.$TERRAFORM_PRIVATE_REPO_NAME $i
    done
  done
}

# Users
import_users () {
  for i in $(curl -s "${API_URL_PREFIX}/orgs/$ORG/members?access_token=$GITHUB_TOKEN&per_page=100" | jq -r 'sort_by(.login) | .[] | .login'); do

  cat >> github-users.tf << EOF
resource "github_membership" "$i" {
  username        = "$i"
  role            = "member"
}
EOF
    terraform import github_membership.$i $ORG:$i
  done
}

# Teams
import_teams () {
  for i in $(curl -s "${API_URL_PREFIX}/orgs/$ORG/teams?access_token=$GITHUB_TOKEN&per_page=100" -H "Accept: application/vnd.github.hellcat-preview+json" | jq -r 'sort_by(.name) | .[] | .id'); do
  
    TEAM_NAME=$(curl -s "${API_URL_PREFIX}/teams/$i?access_token=$GITHUB_TOKEN&per_page=100" -H "Accept: application/vnd.github.hellcat-preview+json" | jq -r .name)

    TEAM_PRIVACY=$(curl -s "${API_URL_PREFIX}/teams/$i?access_token=$GITHUB_TOKEN&per_page=100" -H "Accept: application/vnd.github.hellcat-preview+json" | jq -r .privacy)
  
    TEAM_DESCRIPTION=$(curl -s "${API_URL_PREFIX}/teams/$i?access_token=$GITHUB_TOKEN&per_page=100" -H "Accept: application/vnd.github.hellcat-preview+json" | jq -r .description)
  
    if [[ "$TEAM_PRIVACY" == "closed" ]]; then
      cat >> github-teams-$TEAM_NAME.tf << EOF
resource "github_team" "$TEAM_NAME" {
  name        = "$TEAM_NAME"
  description = "$TEAM_DESCRIPTION"
  privacy     = "closed"
}
EOF
    elif [[ "$TEAM_PRIVACY" == "secret" ]]; then
      cat >> github-teams-$TEAM_NAME.tf << EOF
resource "github_team" "$TEAM_NAME" {
  name        = "$TEAM_NAME"
  description = "$TEAM_DESCRIPTION"
  privacy     = "secret"
}
EOF
    fi

    terraform import github_team.$TEAM_NAME $i
  done
}

# Team Memberships 
import_team_memberships () {
  for i in $(curl -s "${API_URL_PREFIX}/orgs/$ORG/teams?access_token=$GITHUB_TOKEN&per_page=100" -H "Accept: application/vnd.github.hellcat-preview+json" | jq -r 'sort_by(.name) | .[] | .id'); do
  
  TEAM_NAME=$(curl -s "${API_URL_PREFIX}/teams/$i?access_token=$GITHUB_TOKEN&per_page=100" -H "Accept: application/vnd.github.hellcat-preview+json" | jq -r .name)
  
    for j in $(curl -s "${API_URL_PREFIX}/teams/$i/members?access_token=$GITHUB_TOKEN&per_page=100" -H "Accept: application/vnd.github.hellcat-preview+json" | jq -r .[].login); do
    
      TEAM_ROLE=$(curl -s "${API_URL_PREFIX}/teams/$i/memberships/$j?access_token=$GITHUB_TOKEN&per_page=100" -H "Accept: application/vnd.github.hellcat-preview+json" | jq -r .role)

      if [[ "$TEAM_ROLE" == "maintainer" ]]; then
        cat >> github-team-memberships-$TEAM_NAME.tf << EOF
resource "github_team_membership" "$TEAM_NAME-$j" {
  username    = "$j"
  team_id     = "\${github_team.$TEAM_NAME.id}"
  role        = "maintainer"
}
EOF
      elif [[ "$TEAM_ROLE" == "member" ]]; then
        cat >> github-team-memberships-$TEAM_NAME.tf << EOF
resource "github_team_membership" "$TEAM_NAME-$j" {
  username    = "$j"
  team_id     = "\${github_team.$TEAM_NAME.id}"
  role        = "member"
}
EOF
      fi
      terraform import github_team_membership.$TEAM_NAME-$j $i:$j
    done
  done
}

get_team_pagination () {
    team_pages=$(curl -I "${API_URL_PREFIX}/orgs/$ORG/repos?access_token=$GITHUB_TOKEN&per_page=100" | grep -Eo '&page=\d+' | grep -Eo '[0-9]+' | tail -1;)
    echo ${team_pages:-1}
}
  # This function uses the out from above and creates an array counting from 1->$ 
limit_team_pagination () {
  seq $(get_team_pagination)
}

get_team_ids () {
  curl -s "${API_URL_PREFIX}/orgs/$ORG/teams?access_token=$GITHUB_TOKEN&per_page=100" -H "Accept: application/vnd.github.hellcat-preview+json" | jq -r 'sort_by(.name) | .[] | .id'
}

get_team_repos () {
  for PAGE in $(limit_team_pagination); do

    for i in $(curl -s "${API_URL_PREFIX}/teams/$TEAM_ID/repos?access_token=$GITHUB_TOKEN&page=$PAGE&per_page=100" | jq -r 'sort_by(.name) | .[] | .name'); do
    
    TERRAFORM_TEAM_REPO_NAME=$(echo $i | tr  "."  "-")
    TEAM_NAME=$(curl -s "${API_URL_PREFIX}/teams/$TEAM_ID?access_token=$GITHUB_TOKEN" | jq -r .name)

    ADMIN_PERMS=$(curl -s "${API_URL_PREFIX}/teams/$TEAM_ID/repos/$ORG/$i?access_token=$GITHUB_TOKEN" -H "Accept: application/vnd.github.v3.repository+json" | jq -r .permissions.admin )
    PUSH_PERMS=$(curl -s "${API_URL_PREFIX}/teams/$TEAM_ID/repos/$ORG/$i?access_token=$GITHUB_TOKEN" -H "Accept: application/vnd.github.v3.repository+json" | jq -r .permissions.push )
    PULL_PERMS=$(curl -s "${API_URL_PREFIX}/teams/$TEAM_ID/repos/$ORG/$i?access_token=$GITHUB_TOKEN" -H "Accept: application/vnd.github.v3.repository+json" | jq -r .permissions.pull )
  
    if [[ "$ADMIN_PERMS" == "true" ]]; then
      cat >> github-teams-$TEAM_NAME.tf << EOF
resource "github_team_repository" "$TEAM_NAME-$TERRAFORM_TEAM_REPO_NAME" {
  team_id    = "$TEAM_ID"
  repository = "$i"
  permission = "admin"
}

EOF
    elif [[ "$PUSH_PERMS" == "true" ]]; then
      cat >> github-teams-$TEAM_NAME.tf << EOF
resource "github_team_repository" "$TEAM_NAME-$TERRAFORM_TEAM_REPO_NAME" {
  team_id    = "$TEAM_ID"
  repository = "$i"
  permission = "push"
}

EOF
    elif [[ "$PULL_PERMS" == "true" ]]; then
      cat >> github-teams-$TEAM_NAME.tf << EOF
resource "github_team_repository" "$TEAM_NAME-$TERRAFORM_TEAM_REPO_NAME" {
  team_id    = "$TEAM_ID"
  repository = "$i"
  permission = "pull"
}

EOF
    fi
    terraform import github_team_repository.$TEAM_NAME-$TERRAFORM_TEAM_REPO_NAME $TEAM_ID:$i
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
import_private_repos
import_users
import_all_team_resources
