#!/bin/bash
RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
PUR='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m'

echo -e "${CYAN}*-------------------*---------------------*${NC}"
echo -e "${YEL}* Check MDM - Skip MDM Auto for MacOS by *${NC}"
echo -e "${RED}*             SKIPMDM.COM                *${NC}"
echo -e "${RED}*            Phoenix Team                *${NC}"
echo -e "${CYAN}*-------------------*---------------------*${NC}"
echo ""
PS3='Please enter your choice: '
options=("Autoypass on Recovery" "Reboot")
select opt in "${options[@]}"; do
    case $opt in
    "Autoypass on Recovery")
        echo -e "${GRN}Bypass on Recovery"
        if [ -d "/Volumes/Macintosh HD2 - Data" ]; then
            sudo diskutil rename "Macintosh HD2 - Data" "Data"
        fi
        
        echo -e "${GRN}Create a new user / Tạo User mới"
        echo -e "${BLU}Press Enter to continue, Note: Leaving it blank will default to the automatic user"
        
        echo -e "Enter the username (Default: Apple)"
        read realName
        realName="${realName:=Apple}"
        
        echo -e "${BLU}Nhận username ${RED}WRITE WITHOUT SPACES${GRN} (Default: Apple)"
        read username
        username="${username:=Apple}"
        
        echo -e "${BLU}Enter the password (default: 1234)"
        read passw
        passw="${passw:=1234}"
        
        dscl_path='/Volumes/Data/private/var/db/dslocal/nodes/Default'
        if [ ! -d "$dscl_path" ]; then
            echo -e "${RED}Error: Directory $dscl_path does not exist. Exiting.${NC}"
            exit 1
        fi
        
        echo -e "${GRN}Creating User"
        sudo dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" || { echo -e "${RED}Error creating user${NC}"; exit 1; }
        sudo dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UserShell "/bin/zsh"
        sudo dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" RealName "$realName"
        sudo dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UniqueID "501"
        sudo dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" PrimaryGroupID "20"
        
        sudo mkdir -p "/Volumes/Data/Users/$username"
        sudo dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" NFSHomeDirectory "/Users/$username"
        sudo dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$username" "$passw"
        sudo dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership "$username"
        
        if [ -f "/Volumes/Macintosh HD2/etc/hosts" ]; then
            sudo sh -c "echo '0.0.0.0 deviceenrollment.apple.com' >> /Volumes/Macintosh\ HD2/etc/hosts"
            sudo sh -c "echo '0.0.0.0 mdmenrollment.apple.com' >> /Volumes/Macintosh\ HD2/etc/hosts"
            sudo sh -c "echo '0.0.0.0 iprofiles.apple.com' >> /Volumes/Macintosh\ HD2/etc/hosts"
            echo -e "${GRN}Successfully blocked host${NC}"
        else
            echo -e "${RED}Error: /Volumes/Macintosh HD2/etc/hosts not found.${NC}"
        fi
        
        sudo touch /Volumes/Data/private/var/db/.AppleSetupDone
        sudo rm -rf /Volumes/Macintosh\ HD2/var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord
        sudo rm -rf /Volumes/Macintosh\ HD2/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound
        sudo touch /Volumes/Macintosh\ HD2/var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled
        sudo touch /Volumes/Macintosh\ HD2/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound
        
        echo -e "${CYAN}------ Autobypass SUCCESSFULLY ------${NC}"
        echo -e "${CYAN}------ Exit Terminal , Reset Macbook and ENJOY ! ------${NC}"
        break
        ;;
    
    "Reboot")
        echo "Rebooting..."
        sudo reboot
        break
        ;;
    
    *) echo "Invalid option $REPLY" ;;
    esac
done
