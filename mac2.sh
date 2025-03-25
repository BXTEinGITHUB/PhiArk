#!/bin/bash
set -euo pipefail

# Set PATH to ensure commands are found in recovery mode
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# Color definitions for terminal output
RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

echo -e "${CYAN}*-------------------*---------------------*${NC}"
echo -e "${YEL}*    MDM Check - macOS MDM Bypass Tool    *${NC}"
echo -e "${RED}*           SKIPMDM.COM                   *${NC}"
echo -e "${CYAN}*-------------------*---------------------*${NC}"
echo ""

#-------------------
# Disk Selection
#-------------------
echo -e "${GRN}Please select your disks:${NC}"
echo -e "${YEL}Available disks:${NC}"
ls /Volumes
echo ""

read -p "Enter system disk name (default: Macintosh HD): " sysdisk
sysdisk=${sysdisk:-"Macintosh HD"}
sysdisk_path="/Volumes/${sysdisk}"  # System disk path

read -p "Enter data disk name (default: Macintosh HD - Data): " datadisk
datadisk=${datadisk:-"Macintosh HD - Data"}
datadisk_path="/Volumes/${datadisk}"  # Data disk path

#-------------------
# Critical Paths
#-------------------
dscl_path="${datadisk_path}/private/var/db/dslocal/nodes/Default"
config_profiles_path="${sysdisk_path}/var/db/ConfigurationProfiles/Settings"

#-------------------
# Main Menu
#-------------------
PS3='Select an option: '
options=("MDM Bypass (Recovery Mode)" "Reboot" "Exit")
select opt in "${options[@]}"; do
  case $opt in
  "MDM Bypass (Recovery Mode)")
    echo -e "${GRN}[Executing MDM bypass in Recovery Mode...]${NC}"
    
    # Check if data disk is mounted
    if [ ! -d "${datadisk_path}" ]; then
      echo -e "${RED}Error: Data disk is not mounted. Please check the disk name.${NC}"
      exit 1
    fi

    # Check critical directory exists
    if [ ! -d "${dscl_path}" ]; then
      echo -e "${RED}Error: Directory ${dscl_path} does not exist. Please check the data disk.${NC}"
      exit 1
    fi

    #---------- User Creation ----------
    echo -e "${CYAN}=== User Creation ===${NC}"
    echo -e "${BLU}Hint: Press enter to use the default values${NC}"
    
    read -p "Enter full name (default: Apple): " realName
    realName=${realName:-"Apple"}
    
    read -p "Enter username (no spaces) (default: Apple): " username
    username=${username:-"Apple"}
    if [[ "$username" =~ [^a-zA-Z0-9] ]]; then
      echo -e "${RED}Error: Username must contain only letters and numbers${NC}"
      exit 1
    fi
    
    read -sp "Enter password (default: 1234): " passw
    passw=${passw:-"1234"}
    echo ""

    # Define user's home directory path on the data disk
    user_home="${datadisk_path}/Users/${username}"

    #---------- Critical Directory Check ----------
    if [ ! -d "${dscl_path}" ]; then
      echo -e "${RED}Error: Directory ${dscl_path} does not exist. Please check the data disk.${NC}"
      exit 1
    fi

    #---------- Create User ----------
    echo -e "${GRN}Creating user...${NC}"

    # Clean up any existing user
    dscl -f "${dscl_path}" localhost -delete "/Local/Default/Users/${username}" >/dev/null 2>&1 || true
    rm -rf "${user_home}" >/dev/null 2>&1 || true

    # Get next available UniqueID
    next_id=$(dscl -f "${dscl_path}" localhost -list "/Local/Default/Users" UniqueID | awk '{print $2}' | sort -n | tail -n 1 | awk '{print $1+1}')
    
    # Create user directory
    mkdir -p "${user_home}" || {
      echo -e "${RED}Error: Failed to create user directory ${user_home}${NC}"
      exit 1
    }

    # Set user attributes
    dscl -f "${dscl_path}" localhost -create "/Local/Default/Users/${username}" UserShell "/bin/zsh"
    dscl -f "${dscl_path}" localhost -create "/Local/Default/Users/${username}" RealName "${realName}"
    dscl -f "${dscl_path}" localhost -create "/Local/Default/Users/${username}" UniqueID "${next_id}"
    dscl -f "${dscl_path}" localhost -create "/Local/Default/Users/${username}" PrimaryGroupID "20"
    dscl -f "${dscl_path}" localhost -create "/Local/Default/Users/${username}" NFSHomeDirectory "/Users/${username}"
    dscl -f "${dscl_path}" localhost -passwd "/Local/Default/Users/${username}" "${passw}"
    dscl -f "${dscl_path}" localhost -append "/Local/Default/Groups/admin" GroupMembership "${username}"

    #---------- Block MDM Server ----------
    echo -e "${CYAN}=== Modifying Hosts File ===${NC}"
    hosts_path="${sysdisk_path}/etc/hosts"
    if [ -f "${hosts_path}" ]; then
      echo "0.0.0.0 deviceenrollment.apple.com" >> "${hosts_path}"
      echo -e "${GRN}Successfully blocked the MDM server${NC}"
    else
      echo -e "${RED}Warning: Hosts file not found, skipping this step${NC}"
    fi

    #---------- Modify System Configuration ----------
    echo -e "${CYAN}=== Modifying System Configuration ===${NC}"
    touch "${datadisk_path}/private/var/db/.AppleSetupDone"
    rm -rf "${config_profiles_path}/.cloudConfigHasActivationRecord"
    rm -rf "${config_profiles_path}/.cloudConfigRecordFound"
    touch "${config_profiles_path}/.cloudConfigProfileInstalled"
    touch "${config_profiles_path}/.cloudConfigRecordNotFound"

    echo -e "${CYAN}====== MDM bypass completed ======${NC}"
    echo -e "${YEL}Please exit Terminal and reboot your Mac${NC}"
    trap 'rm -rf "${user_home}"; dscl -f "${dscl_path}" localhost -delete "/Local/Default/Users/${username}"' EXIT
    break
    ;;

  "Reboot")
    echo -e "${GRN}Rebooting the system...${NC}"
    reboot
    ;;

  "Exit")
    echo -e "${GRN}Exiting...${NC}"
    exit 0
    ;;

  *)
    echo -e "${RED}Invalid option: $REPLY${NC}"
    ;;
  esac
done

exec > >(tee -a "${datadisk_path}/mdm_bypass.log") 2>&1
