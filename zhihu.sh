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
        if [ -d "/Volumes/Macintosh HD - Data" ]; then
            sudo diskutil rename "Macintosh HD - Data" "Data"
        fi
        
        echo -e "${GRN}Create a new user / Tạo User mới"
        echo -e "${BLU}Press Enter to continue, Note: Leaving it blank will default to the automatic user / Nhấn Enter để tiếp tục, Lưu ý: có thể không điền sẽ tự động nhận User mặc định"
        
        # Read username and handle default values
        echo -e "Enter the username (Default: Apple) / Nhập tên User (Mặc định: Apple)"
        read realName
        realName="${realName:=Apple}"
        
        echo -e "${BLUE}Nhận username ${RED}WRITE WITHOUT SPACES / VIẾT LIỀN KHÔNG DẤU ${GRN} (Mặc định: Apple)"
        read username
        username="${username:=Apple}"
        
        # Read password and handle default values
        echo -e "${BLUE}Enter the password (default: 1234) / Nhập mật khẩu (mặc định: 1234)"
        read passw
        passw="${passw:=1234}"
        
        # Define the dscl path and check if it exists
        dscl_path='/Volumes/Data/private/var/db/dslocal/nodes/Default'
        if [ ! -d "$dscl_path" ]; then
            echo -e "${RED}Error: Directory $dscl_path does not exist. Exiting.${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}Creating User / Đang tạo User"
        
        # Create user with proper permissions and check for errors
        sudo dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" || { echo -e "${RED}Error creating user${NC}"; exit 1; }
        sudo dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UserShell "/bin/zsh"
        sudo dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" RealName "$realName"
        sudo dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UniqueID "501"
        sudo dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" PrimaryGroupID "20"
        
        sudo mkdir -p "/Volumes/Data/Users/$username"
        sudo dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" NFSHomeDirectory "/Users/$username"
        sudo dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$username" "$passw"
        sudo dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership "$username"
        
        # Modify hosts file with error handling
        if [ -f "/Volumes/Macintosh HD/etc/hosts" ]; then
            sudo sh -c "echo '0.0.0.0 deviceenrollment.apple.com' >> /Volumes/Macintosh\\ HD/etc/hosts"
            sudo sh -c "echo '0.0.0.0 mdmenrollment.apple.com' >> /Volumes/Macintosh\\ HD/etc/hosts"
            sudo sh -c "echo '0.0.0.0 iprofiles.apple.com' >> /Volumes/Macintosh\\ HD/etc/hosts"
            echo -e "${GREEN}Successfully blocked host / Thành công chặn host${NC}"
        else
            echo -e "${RED}Error: /Volumes/Macintosh HD/etc/hosts not found.${NC}"
        fi
        
        # Create / remove files with proper paths
        sudo touch /Volumes/Data/private/var/db/.AppleSetupDone
        sudo rm -rf /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord
        sudo rm -rf /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound
        sudo touch /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled
        sudo touch /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound
        
        echo -e "${CYAN}------ Autobypass SUCCESSFULLY / Autobypass HOÀN TẤT ------${NC}"
        echo -e "${CYAN}------ Exit Terminal , Reset Macbook and ENJOY ! ------${NC}"
        break
        ;;
    
    "Disable Notification (SIP)")
        echo -e "${RED}Please Insert Your Password To Proceed${NC}"
        sudo rm /var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord
        sudo rm /var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound
        sudo touch /var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled
        sudo touch /var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound
        break
        ;;
    
    "Disable Notification (Recovery)")
        sudo rm -rf /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord
        sudo rm -rf /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound
        sudo touch /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled
        sudo touch /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound
        break
        ;;
    
    "Check MDM Enrollment")
        echo ""
        echo -e "${GRN}Check MDM Enrollment. Error is success${NC}"
        echo ""
        echo -e "${RED}Please Insert Your Password To Proceed${NC}"
        echo ""
        sudo profiles show -type enrollment
        break
        ;;
    
    "Exit")
        echo "Rebooting..."
        sudo reboot
        break
        ;;
    
    *) echo "Invalid option $REPLY" ;;
    esac
done
