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
# This script cleans up a VMware-based lab environment by powering off and
# deleting all virtual machines located inside a specified workload sandbox
# VM folder.
#
# The script is intended to be used after completing demos, enablement, or
# test deployments, and helps return the lab environment to a clean state.
#
# The bastion host VM is explicitly excluded from deletion to ensure continued
# access to the environment.
#
# The script requires the user to provide vCenter connection details and the
# full inventory path of the target VM folder. All inputs are validated and
# must be confirmed by the user before any destructive actions are performed.
#
# This script performs the following actions:
# - Connects to vCenter using govc
# - Lists all VMs in the specified VM folder
# - Powers off each VM (except the bastion host)
# - Deletes the powered-off VMs
#
# ⚠️ WARNING:
# This script performs irreversible delete operations. Ensure the correct VM
# folder is provided and review the confirmation prompt carefully before
# proceeding.
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
# Reset variables (script + GOVC env) for safe re-runs
#-------------------------------------------------------------

# Unset GOVC environment variables (avoid stale sessions)
unset GOVC_URL GOVC_USERNAME GOVC_PASSWORD GOVC_INSECURE GOVC_DATACENTER DC_NAME VCENTER_URL VCENTER_USERNAME VCENTER_PASSWORD GOVC_VM_FOLDER_PATH

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
echo " |  VM Cleanup Script – Power Off and Delete Workload VMs  | "
echo " |        This script will power off and permanently       | "
echo " |                  delete virtual machines.               | "
echo "  ---------------------------------------------------------  "
echo ""
echo " --- Starting the VM Clean Up script..."
echo -e "${NC}"

echo " ================================================================================== "
echo ""

#===================================================================================

#-------------------------------------------------------------
# Collect and Confirm User Inputs
#-------------------------------------------------------------

echo -e "${YELLOW} Collect & Confirm vCenter Cleanup Information${NC}"
echo -e "${YELLOW} --------------------------------------------${NC}"
echo ""

while true; do
  echo -e "${YELLOW} - Please provide the required vCenter information below:${NC}"
  VCENTER_URL=$(read_non_empty "   Enter vCenter URL (e.g. vc.example.com): ")
  VCENTER_USERNAME=$(read_non_empty "   Enter vCenter username: ")
  VCENTER_PASSWORD=$(read_non_empty "   Enter vCenter password: ")
  DC_NAME=$(read_non_empty "   Enter vCenter Datacenter name (e.g. SDDC-Datacenter): ")
  GOVC_VM_FOLDER_PATH=$(read_non_empty "   Enter VM folder full path (e.g. /SDDC-Datacenter/vm/Workloads/sandbox-r5vnx): ")
  echo ""

  echo -e "${YELLOW} - Please review the provided information below & confirm (Y/N):${NC}"
  echo "   ----------------------------------------"
  echo "   vCenter URL        : $VCENTER_URL"
  echo "   vCenter Username   : $VCENTER_USERNAME"
  echo "   vCenter Password   : $VCENTER_PASSWORD"
  echo "   Datacenter Name    : $DC_NAME"
  echo "   VM Folder Path     : $GOVC_VM_FOLDER_PATH"
  echo "   ----------------------------------------"
  echo ""

  if confirm_yn "   Are the above provided information correct? (Y/N): "; then
    echo -e "${GREEN}   Input confirmed. Proceeding...${NC}"
    break
  else
    echo -e "${YELLOW}   Re-entering input details...${NC}"
    echo ""
  fi
done

#-------------------------------------------------------------
# Export govc Environment Variables
#-------------------------------------------------------------

export GOVC_URL="$VCENTER_URL"
export GOVC_USERNAME="$VCENTER_USERNAME"
export GOVC_PASSWORD="$VCENTER_PASSWORD"
export GOVC_DATACENTER="$DC_NAME"
export GOVC_INSECURE=1

#-------------------------------------------------------------
# Section Summary
#-------------------------------------------------------------
# Variables set:
# - GOVC_URL
# - GOVC_USERNAME
# - GOVC_PASSWORD
# - GOVC_DATACENTER
# - GOVC_VM_FOLDER_PATH
#-------------------------------------------------------------

echo ""
echo " ================================================================================== "
echo ""

#===================================================================================

#-------------------------------------------------------------
# Collect All VMs In Folder (Except Bastion)
#-------------------------------------------------------------

echo -e "${YELLOW} Scanning VM Folder And Preparing Cleanup...${NC}"
echo -e "${YELLOW} -----------------------------------------${NC}"
echo ""

# List VMs in the provided folder (names only)
mapfile -t VMS_IN_FOLDER < <(govc ls "$GOVC_VM_FOLDER_PATH" 2>/dev/null | awk -F/ '{print $NF}')

if [[ "${#VMS_IN_FOLDER[@]}" -eq 0 ]]; then
  echo -e "${RED}   ERROR: No VMs found in folder: $GOVC_VM_FOLDER_PATH${NC}"
  exit 1
fi

# Keep only VMs that are NOT bastion (anything with 'bastion' in the name is excluded)
VM_DELETE_LIST=()
for vm in "${VMS_IN_FOLDER[@]}"; do
  [[ "$vm" =~ bastion ]] && continue
  VM_DELETE_LIST+=("$vm")
done

if [[ "${#VM_DELETE_LIST[@]}" -eq 0 ]]; then
  echo -e "${YELLOW}   Nothing to delete (only bastion VM(s) found).${NC}"
  exit 0
fi

echo -e "${CYAN} The following VMs will be powered off and deleted:${NC}"
for vm in "${VM_DELETE_LIST[@]}"; do
  echo "   - $vm"
done
echo ""

if ! confirm_yn "Proceed to POWER-OFF and DELETE ALL VMs listed above? (Y/N): "; then
  echo -e "${YELLOW}   Cleanup canceled by user.${NC}"
  exit 0
fi

echo ""
echo " ================================================================================== "
echo ""

#===================================================================================

#-------------------------------------------------------------
# Power-Off + Delete All VMs In Folder (Except Bastion)
#-------------------------------------------------------------

echo -e "${YELLOW} Powering off and deleting VMs...${NC}"
echo -e "${YELLOW} --------------------------------${NC}"
echo ""

for vm in "${VM_DELETE_LIST[@]}"; do
  echo "   Powering-Off & Deleting VM $vm"

  # Power off (ignore errors if already off)
  govc vm.power -off -force "$vm" >/dev/null 2>&1 || true

  sleep 5

  # Delete
  if ! govc vm.destroy "$vm" >/dev/null 2>&1; then
    echo -e "${RED}      ERROR: Failed to delete VM: $vm${NC}"
    exit 1
  fi

  echo "      --- VM $vm powered-off & deleted successfully. Proceeding..."
done

echo ""
echo -e "${GREEN} Cleanup completed successfully.${NC}"
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