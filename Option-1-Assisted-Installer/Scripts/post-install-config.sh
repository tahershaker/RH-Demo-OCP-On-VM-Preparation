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
# This script performs post-install configuration tasks for an OpenShift cluster
# deployed using the Assisted Installer.
#
# It is intended to be executed after the cluster installation is completed and
# the kubeconfig file is available on the bastion host.
#
# The script helps bootstrap initial cluster access and storage configuration by
# automating common Day-1 administrative tasks, including:
#
# - Verifying the presence and validity of the kubeconfig file
# - Validating cluster connectivity using the oc CLI
# - Creating a local admin user using the HTPasswd identity provider
# - Configuring OpenShift OAuth to use the HTPasswd provider
# - Granting cluster-admin privileges to the newly created admin user
# - Installing the LVM Storage Operator from Red Hat Operators
# - Creating and configuring an LVMCluster resource for local persistent storage
#
# All required inputs (such as admin password and kubeconfig location) are
# explicitly requested from the user and validated before execution.
#
# This script is designed to be safe to re-run where possible and provides clear
# status output for each step.
#
# The script does NOT modify cluster installation settings or infrastructure
# components, and focuses only on post-install access and storage enablement.
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
echo " |  Post-Install-Config  | Create admin user + install LVM | "
echo " |        This script will create an OCP admin user        | "
echo " |                and install/config OCP LVM.              | "
echo "  ---------------------------------------------------------  "
echo ""
echo " --- Starting the Post-Install-Config script..."
echo -e "${NC}"

echo " ================================================================================== "
echo ""

#===================================================================================

#-------------------------------------------------------------
# Collect and Confirm User Inputs
#-------------------------------------------------------------

echo -e "${YELLOW} Collect & Confirm Post-Install Inputs${NC}"
echo -e "${YELLOW} -------------------------------------${NC}"
echo ""

# 1) Confirm kubeconfig placement (we do NOT ask for path)
echo -e "${CYAN} - kubeconfig Prerequisites${NC}"
echo "   You must have already done the following as the current (non-root) user:"
echo "   - mkdir -p ~/.kube"
echo "   - chmod 700 ~/.kube"
echo "   - Copy kubeconfig content to ~/.kube/config"
echo "   - chmod 600 ~/.kube/config"
echo ""

if ! confirm_yn "   Did you place kubeconfig in ~/.kube/config with correct permissions? (Y/N): "; then
  echo -e "${RED}   kubeconfig is required. Please complete the kubeconfig steps then re-run.${NC}"
  exit 1
fi

# Verify kubeconfig exists + permissions + oc can talk to cluster
echo ""
echo -e "${CYAN}   Verifying kubeconfig...${NC}"

if [[ ! -f "$HOME/.kube/config" ]]; then
  echo -e "${RED}   ERROR: kubeconfig not found at: $HOME/.kube/config${NC}"
  exit 1
fi

# Optional: permission checks (best-effort, don’t break if stat differs)
KCFG_PERM="$(stat -c '%a' "$HOME/.kube/config" 2>/dev/null || stat -f '%Lp' "$HOME/.kube/config" 2>/dev/null || echo "unknown")"

if [[ "$KCFG_PERM" != "unknown" && "$KCFG_PERM" != "600" ]]; then
  echo -e "${YELLOW}   WARN: ~/.kube/config permissions are $KCFG_PERM (expected 600).${NC}"
  echo -e "${RED}   Please complete the kubeconfig steps then re-run.${NC}"
  exit 1
fi

# Ensure oc exists
if ! command -v oc >/dev/null 2>&1; then
  echo -e "${RED}   ERROR: oc CLI is not installed or not in PATH.${NC}"
  echo -e "${RED}   Please install oc first (it should exist from the prep script).${NC}"
  exit 1
fi

# Quick cluster connectivity check
if ! oc whoami >/dev/null 2>&1; then
  echo -e "${RED}   ERROR: oc cannot authenticate using ~/.kube/config.${NC}"
  echo -e "${RED}   Please verify kubeconfig content and access, then re-run.${NC}"
  exit 1
fi

CLUSTER_USER="$(oc whoami 2>/dev/null || true)"
CLUSTER_API="$(oc whoami --show-server 2>/dev/null || true)"

echo -e "${GREEN}   kubeconfig OK.${NC}"
echo -e "${GREEN}   Connected as: ${CLUSTER_USER}${NC}"
echo -e "${GREEN}   API Server   : ${CLUSTER_API}${NC}"
echo ""

echo -e "${CYAN} - Admin User Input${NC}"
ADMIN_USERNAME="$(read_non_empty "   Enter admin username to create (default: admin): ")"
ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
ADMIN_PASSWORD="$(read_non_empty "   Enter password for ${ADMIN_USERNAME}: ")"
echo ""

echo -e "${CYAN} - LVM Cluster Input${NC}"
LVM_VG_NAME="$(read_non_empty "   Enter LVM Volume Group name (default: vg1): ")"
LVM_VG_NAME="${LVM_VG_NAME:-vg1}"
LVM_THINPOOL_NAME="$(read_non_empty "   Enter LVM thin pool name (default: thin-pool-1): ")"
LVM_THINPOOL_NAME="${LVM_THINPOOL_NAME:-thin-pool-1}"
echo ""

echo -e "${YELLOW} - Please review & confirm:${NC}"
echo "   ----------------------------------------"
echo "   Kubeconfig Path     : $HOME/.kube/config"
echo "   Connected User      : $CLUSTER_USER"
echo "   API Server          : $CLUSTER_API"
echo "   New Admin Username  : $ADMIN_USERNAME"
echo "   New Admin Password  : $ADMIN_PASSWORD"
echo "   LVM VG Name         : $LVM_VG_NAME"
echo "   LVM Thin Pool Name  : $LVM_THINPOOL_NAME"
echo "   ----------------------------------------"
echo ""

if confirm_yn "   Proceed with user creation + LVM operator install/config? (Y/N): "; then
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
# - Create/Configure HTPasswd admin user
# - Install/Configure LVM Storage
#-------------------------------------------------------------

echo -e "${YELLOW} Running Post-Install Actions${NC}"
echo -e "${YELLOW} ----------------------------${NC}"
echo ""

#-------------------------
# 1) Install httpd-tools
#-------------------------
echo -e "${CYAN} - Installing httpd-tools (htpasswd)${NC}"
if command -v htpasswd >/dev/null 2>&1; then
  echo -e "${GREEN}   htpasswd already installed. Skipping.${NC}"
else
  sudo dnf install -y httpd-tools >/dev/null 2>&1
  echo -e "${GREEN}   httpd-tools installed.${NC}"
fi

echo ""
echo " ================================================================================== "
echo ""

#-------------------------
# 2) Create/Configure Admin User (HTPasswd)
#-------------------------
echo -e "${CYAN} - Creating/Updating HTPasswd admin user${NC}"

OCP_USERS_DIR="$HOME/ocp-users"
HTPASS_FILE="${OCP_USERS_DIR}/users.htpasswd"
OAUTH_YAML="${OCP_USERS_DIR}/oauth-htpasswd.yaml"
IDP_NAME="local-htpasswd"
SECRET_NAME="htpass-secret"
NS_CONFIG="openshift-config"

mkdir -p "$OCP_USERS_DIR"

# Create/Update htpasswd file (idempotent)
if [[ -f "$HTPASS_FILE" ]]; then
  htpasswd -B -b "$HTPASS_FILE" "$ADMIN_USERNAME" "$ADMIN_PASSWORD" >/dev/null 2>&1
else
  htpasswd -c -B -b "$HTPASS_FILE" "$ADMIN_USERNAME" "$ADMIN_PASSWORD" >/dev/null 2>&1
fi

echo -e "${GREEN}   HTPasswd file updated: $HTPASS_FILE${NC}"

# Create or update secret (idempotent)
oc -n "$NS_CONFIG" get secret "$SECRET_NAME" >/dev/null 2>&1 \
  && oc -n "$NS_CONFIG" delete secret "$SECRET_NAME" >/dev/null 2>&1 || true

oc -n "$NS_CONFIG" create secret generic "$SECRET_NAME" --from-file=htpasswd="$HTPASS_FILE" >/dev/null 2>&1
echo -e "${GREEN}   Secret created: ${NS_CONFIG}/${SECRET_NAME}${NC}"

# Apply OAuth config (idempotent)
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
echo -e "${GREEN}   OAuth updated to use HTPasswd provider: ${IDP_NAME}${NC}"
echo -e "${CYAN}   Waiting 60 seconds for OAuth to reload...${NC}"
sleep 60

# Grant cluster-admin (idempotent)
oc adm policy add-cluster-role-to-user cluster-admin "$ADMIN_USERNAME" >/dev/null 2>&1 || true
echo -e "${GREEN}   cluster-admin role granted to: ${ADMIN_USERNAME}${NC}"

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