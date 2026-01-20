#!/usr/bin/env bash

#===================================================================================

#-------------------------------------------------------------
# Add strict bash safety & Set trap to handel script interruption
#-------------------------------------------------------------

set -Eeuo pipefail
trap 'echo "\n ---- Script interrupted. Exiting..."; exit 1' INT TERM
trap 'rc=$?; echo "\n ---- ERROR: line ${LINENO}: ${BASH_COMMAND}" >&2; exit $rc' ERR

#===================================================================================

#-------------------------------------------------------------
# Script Description
#-------------------------------------------------------------

################################################################################

################################################################################

#===================================================================================

#-------------------------------------------------------------
# Set Colors For Outputs
#-------------------------------------------------------------

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
GREY='\033[0;90m'
BLUE='\033[0;34m'
BRIGHT_BLUE='\033[1;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'   # Reset / No Color

#===================================================================================

#-------------------------------------------------------------
# Create Functions To Be Used In Script
#-------------------------------------------------------------

# Function to Read Non-Empty Input (Rejects empty or whitespace-only)
read_non_empty() {
  local prompt="$1"
  local value

  while true; do
    read -rp "$prompt" value
    value="$(echo "$value" | xargs)"

    if [[ -z "$value" ]]; then
      echo -e "${RED}   Input cannot be empty. Please try again.${NC}" >&2
      echo ""
      continue
    fi

    echo "$value"
    return 0
  done
}

#------------------------------------------------------------------------------

# Function to Confirm user input Y/N
confirm_yn() {
  local prompt="$1" ans
  while true; do
    read -rp "$prompt" ans
    case "$ans" in
      [Yy]) return 0 ;;
      [Nn]) return 1 ;;
      *) echo -e "${RED}   Invalid input. Please enter Y or N only.${NC}" >&2 ;;
    esac
  done
}

#===================================================================================

#-------------------------------------------------------------
# Print Staring Script Message
#-------------------------------------------------------------

echo -e "${RED}"
echo "  ---------------------------------------------------------  "
echo " | =========  Dedicated DNS Records Environment  ========= | "
echo " | =========          IPI Installer Prep         ========= | "
echo " | ------------------------------------------------------- | "
echo " |         Post-Install-Config | Create admin user         | "
echo " |        This script will create an OCP admin user        | "
echo " |           and configure the required password           | "
echo "  ---------------------------------------------------------  "
echo ""
echo " --- Starting the create-admin-user script..."
echo -e "${NC}"

echo " ================================================================================== "
echo ""

#===================================================================================

#-------------------------------------------------------------
# Collect and Confirm User Inputs
#-------------------------------------------------------------

echo -e "${YELLOW} Collect & Confirm Admin User Inputs${NC}"
echo -e "${YELLOW} -----------------------------------${NC}"
echo ""

# Check user executed the ecport command to set the KUBECONFIG
echo -e "${CYAN} - kubeconfig export prerequisite (manual)${NC}"
echo -e "${GREY}   You must run the export command shown by the installer in THIS terminal session.${NC}"
echo -e "${GREY}   Example:${NC}"
echo -e "${GREEN}   export KUBECONFIG=/home/lab-user/openshift-install-dir/2x9pq/auth/kubeconfig${NC}"
echo ""

if ! confirm_yn "   Did you run the export KUBECONFIG command in this same terminal session? (Y/N): "; then
  echo ""
  echo -e "${RED}   Please run the export command first, then re-run this script from the SAME terminal session.${NC}"
  echo -e "${RED}   Example:${NC}"
  echo -e "${GREEN}   export KUBECONFIG=/home/lab-user/openshift-install-dir/<cluster>/auth/kubeconfig${NC}"
  echo ""
  exit 1
fi

# Check env var exists
echo -e "${CYAN}   Verifying KUBECONFIG is set...${NC}"
if [[ -z "${KUBECONFIG:-}" ]]; then
  echo -e "${RED}   ERROR: KUBECONFIG is not set in this terminal session.${NC}"
  echo -e "${RED}   Run the export command, then re-run this script.${NC}"
  exit 1
fi

echo "      Verified. Proceeding..."
echo ""

# Check kubeconfig file exists
echo -e "${CYAN}   Verifying kubeconfig file exists...${NC}"
if [[ ! -f "${KUBECONFIG}" ]]; then
  echo -e "${RED}   ERROR: kubeconfig file not found at:${NC}"
  echo -e "${RED}   ${KUBECONFIG}${NC}"
  echo -e "${RED}   Make sure the path is correct and IPI installation completed then re-run this script.${NC}"
  exit 1
fi

echo "      Verified. Proceeding..."
echo ""

# Ensure oc exists
echo -e "${CYAN}   Verifying oc CLi is installed...${NC}"
if ! command -v oc >/dev/null 2>&1; then
  echo -e "${RED}   ERROR: oc CLI is not installed or not in PATH.${NC}"
  echo -e "${RED}   Please install oc first (it should exist from the prep script) then re-run this script.${NC}"
  exit 1
fi

echo "      Verified. Proceeding..."
echo ""

# Connectivity check
echo -e "${CYAN}   Verifying cluster connectivity...${NC}"
if ! oc whoami >/dev/null 2>&1; then
  echo -e "${RED}   ERROR: oc cannot authenticate using KUBECONFIG=${KUBECONFIG}${NC}"
  echo -e "${RED}   Re-run the export command and try again.${NC}"
  exit 1
fi

echo "      Verified. Proceeding..."
echo ""

CLUSTER_USER="$(oc whoami 2>/dev/null || true)"
CLUSTER_API="$(oc whoami --show-server 2>/dev/null || true)"

echo -e "${GREEN}   kubeconfig and access check is successful.${NC}"
echo "   Connected as : ${CLUSTER_USER}"
echo "   API Server   : ${CLUSTER_API}"
echo ""

# 2) Admin user inputs (username fixed to admin)
echo -e "${CYAN} - Admin User Input${NC}"
ADMIN_USERNAME="admin"
ADMIN_PASSWORD="$(read_non_empty "   Enter password for ${ADMIN_USERNAME} user: ")"

# Ensure no new-line or spaces in the provided password
ADMIN_PASSWORD="$(printf '%s' "$ADMIN_PASSWORD" | tr -d '\r\n' | xargs)"

echo ""
echo -e "${YELLOW} - Please review & confirm:${NC}"
echo "   ----------------------------------------"
printf "   Admin Username  : %s\n" "$ADMIN_USERNAME"
printf "   Admin Password  : %s\n" "$ADMIN_PASSWORD"
echo "   ----------------------------------------"
echo ""

if confirm_yn "   Proceed with user creation? (Y/N): "; then
  echo -e "${GREEN}   Input confirmed. Proceeding...${NC}"
else
  echo -e "${RED}   Not confirmed. Exiting.${NC}"
  exit 1
fi

#Print Separator
echo ""
echo " ================================================================================== "
echo ""

#===================================================================================

#-------------------------------------------------------------
# Post-Install Actions
# - Install httpd-tools
#-------------------------------------------------------------

echo -e "${YELLOW} Installing httpd-tools (htpasswd)...${NC}"
echo -e "${YELLOW} ------------------------------------${NC}"
echo ""

if command -v htpasswd >/dev/null 2>&1; then
  echo -e "${GREEN}   htpasswd already installed. Skipping.${NC}"
else
  sudo dnf install -y httpd-tools >/dev/null 2>&1
  echo -e "${GREEN}   httpd-tools installed.${NC}"
fi

echo ""
echo " ================================================================================== "
echo ""

#===================================================================================

#-------------------------------------------------------------
# Post-Install Actions
# - Create/Configure HTPasswd admin user
#-------------------------------------------------------------

echo -e "${YELLOW} Creating/Updating admin user...${NC}"
echo -e "${YELLOW} -------------------------------${NC}"
echo ""

OCP_USERS_DIR="$HOME/ocp-users"
HTPASS_FILE="${OCP_USERS_DIR}/users.htpasswd"
OAUTH_YAML="${OCP_USERS_DIR}/oauth-htpasswd.yaml"
IDP_NAME="local-htpasswd"
SECRET_NAME="admin-htpass-secret"
NS_CONFIG="openshift-config"

mkdir -p "$OCP_USERS_DIR"

# Create/Update htpasswd file (idempotent)
echo "   Creating/Updating HTPasswd file..."
if [[ -f "$HTPASS_FILE" ]]; then
  htpasswd -B -b "$HTPASS_FILE" "$ADMIN_USERNAME" "$ADMIN_PASSWORD" >/dev/null 2>&1
else
  htpasswd -c -B -b "$HTPASS_FILE" "$ADMIN_USERNAME" "$ADMIN_PASSWORD" >/dev/null 2>&1
fi

echo "      HTPasswd file updated: $HTPASS_FILE"

# Create or update secret (safe re-run)
echo "   Creating/Updating ${ADMIN_USERNAME} user secret..."
oc -n "$NS_CONFIG" create secret generic "$SECRET_NAME" --from-file=htpasswd="$HTPASS_FILE" --dry-run=client -o yaml | oc apply -f - >/dev/null 2>&1
echo "      Secret created/updated: ${NS_CONFIG}/${SECRET_NAME}"

# Apply OAuth config (idempotent)
echo "   Creating OAUTH to use HTPasswd provider..."
cat > "$OAUTH_YAML" <<EOF
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: ${IDP_NAME}
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: ${SECRET_NAME}
EOF

oc apply -f "$OAUTH_YAML" >/dev/null 2>&1
echo "      OAuth updated to use HTPasswd provider: ${IDP_NAME}"
echo "   ----------------------------------------------"
echo "   ---> Waiting 60 seconds for OAuth to reload..."
echo "   ----------------------------------------------"
sleep 60

# Grant cluster-admin (idempotent)
echo "   Granting cluster-admin to ${ADMIN_USERNAME} user..."
oc adm policy add-cluster-role-to-user cluster-admin "$ADMIN_USERNAME" >/dev/null 2>&1 || true
echo "      cluster-admin role granted to: ${ADMIN_USERNAME}"
echo "   Verifying permissions for ${ADMIN_USERNAME}..."

CAN_GET_PM="$(oc auth can-i get packagemanifests -n openshift-marketplace --as="$ADMIN_USERNAME")"
CAN_LIST_CS="$(oc auth can-i list catalogsources -n openshift-marketplace --as="$ADMIN_USERNAME")"

echo "      ---> Can ${ADMIN_USERNAME} get marketplace PackageManifests? : ${CAN_GET_PM}"
echo "      ---> Can ${ADMIN_USERNAME} list marketplace CatalogSources? : ${CAN_LIST_CS}"


if [[ "$CAN_GET_PM" != "yes" ]]; then
  echo -e "${RED}   ERROR: ${ADMIN_USERNAME} does NOT have required permissions.${NC}"
  echo -e "${RED}   Ensure cluster-admin role is correctly assigned.${NC}"
  echo -e "${RED}   using the oc with the default kubeconfig - oc adm policy add-cluster-role-to-user cluster-admin admin${NC}"
fi

if [[ "$CAN_LIST_CS" != "yes" ]]; then
  echo -e "${RED}   ERROR: ${ADMIN_USERNAME} does NOT have required permissions.${NC}"
  echo -e "${RED}   Ensure cluster-admin role is correctly assigned.${NC}"
  echo -e "${RED}   using the oc with the default kubeconfig - oc adm policy add-cluster-role-to-user cluster-admin admin${NC}"
fi

echo ""
echo -e "${GREEN}   Admin user has been configured successfuly.${NC}"

echo ""
echo " ================================================================================== "
echo ""

#===================================================================================

#-------------------------------------------------------------
# Print Script Completed
#-------------------------------------------------------------

echo ""
echo -e "${RED}"
echo "  --------------------------------------------------------------------------------  "
echo " | =====================         Script Completed           ===================== | "
echo " | =====================            * Enjoy *               ===================== | "
echo "  --------------------------------------------------------------------------------  "
echo " ================================================================================== "
echo ""
echo -e "${NC}"
echo " ================================================================================== "
echo ""

#===================================================================================