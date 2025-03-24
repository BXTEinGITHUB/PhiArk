#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# 版本信息（更新版本号以体现改进）
readonly SCRIPT_VERSION="1.3.1"

# ======================= 颜色与格式 =======================
readonly RED='\033[1;31m'     # 红色
readonly GRN='\033[1;32m'     # 绿色
readonly BLU='\033[1;34m'     # 蓝色
readonly YEL='\033[1;33m'     # 黄色
readonly PUR='\033[1;35m'     # 紫色
readonly CYAN='\033[1;36m'    # 青色
readonly NC='\033[0m'         # 无颜色

# ======================= 日志函数 =======================
log_info() {
  printf "${GRN}[INFO]${NC} %s\n" "$1"
}

log_warn() {
  printf "${YEL}[WARN]${NC} %s\n" "$1"
}

log_error() {
  printf "${RED}[ERROR]${NC} %s\n" "$1"
}

# ======================= 使用说明 =======================
usage() {
  cat <<EOF
${CYAN}MDM Skipper 脚本 v${SCRIPT_VERSION}${NC}
用法: $0 [选项]

选项:
  autobypass           执行恢复模式绕过（自动创建用户、修改 hosts 等）
  disable_notification 停用通知（自动识别 SIP 或恢复模式）
  check_mdm            检查 MDM 注册状态
  reboot               重启系统
  block_mdm            屏蔽 MDM 服务
  solve_all            一次性执行所有操作（自动依次执行以上功能）
  manual               显示用户手册
  --non-interactive    非交互模式（使用默认值，不等待提示）
  -h, --help           显示此帮助信息

【彩蛋】你发现了隐藏的小彩蛋！祝你使用愉快！
EOF
}

# ======================= 用户手册 =======================
show_manual() {
  cat <<EOF
================ 用户手册 ================
本脚本旨在帮助用户在 macOS 恢复模式下绕过 MDM 限制，主要功能包括：
  1. 自动绕过：创建新的管理员用户，修改 hosts 文件以屏蔽 MDM 域名，
     并更新 MDM 配置文件以跳过初始设置。
  2. 停用通知：自动识别当前系统模式（SIP 或恢复模式），统一执行停用通知操作，
     删除云配置记录并创建阻断标记文件。
  3. 检查 MDM：显示当前 MDM 注册状态，便于用户确认是否成功绕过。
  4. 屏蔽 MDM 服务：备份并禁用系统中的 mdmclient 及相关启动项，同时更新 hosts 文件屏蔽 MDM 域名。
  5. 一次性执行所有操作：将上述操作依次执行，适合快速全面处理。
  6. 卷扫描选择：提供自动扫描 /Volumes 下所有卷，并支持直接选择系统卷和数据卷，
     解决自动检测不准确或自定义卷名称的情况。

【小彩蛋】PS：传说中凤凰涅槃，正如本脚本助你摆脱束缚般重获新生！祝你好运！

使用提示：
  - 建议在恢复模式下、以 root 权限运行本脚本。
  - 如遇系统提示或错误，请仔细阅读日志信息，并检查相关依赖及路径。
  - 非交互模式下（参数 --non-interactive）将自动使用默认值，请确保默认设置适合你的环境。

===========================================
EOF
  press_enter_to_continue
}

# ======================= 非交互模式判断 =======================
NONINTERACTIVE=0
if [[ "${1:-}" == "--non-interactive" ]]; then
  NONINTERACTIVE=1
  shift
fi

# ======================= 依赖与权限检查 =======================
check_dependency() {
  local cmd
  for cmd in diskutil dscl profiles sw_vers; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log_error "缺少必要的命令: $cmd. 请检查系统环境。"
      exit 1
    fi
  done
}

check_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    log_error "请以 root 权限执行此脚本（建议在恢复模式下运行）。"
    exit 1
  fi
}

# ======================= 检查是否处于恢复模式 =======================
check_recovery_mode() {
  # 通过 sw_vers 判断产品名称中是否包含 "Recovery"，否则给出警告
  local product_name
  product_name=$(sw_vers -productName 2>/dev/null || echo "Unknown")
  if [[ "$product_name" != *"Recovery"* ]]; then
    log_warn "当前系统可能不在 Recovery 模式下运行。部分操作可能失败。"
    if [[ $NONINTERACTIVE -eq 0 ]]; then
      read -p "是否继续执行？(y/n): " cont
      if [[ ! "$cont" =~ ^[Yy]$ ]]; then
        log_info "已取消执行。"
        exit 1
      fi
    else
      log_info "非交互模式下，继续执行。"
    fi
  else
    log_info "检测到在 Recovery 模式下运行。"
  fi
}

# ======================= 卷扫描与选择功能 =======================
# 列出 /Volumes 下的所有目录，并允许用户选择
select_volume() {
  local prompt="$1"
  local volumes=()
  local vol
  for vol in /Volumes/*; do
    if [ -d "$vol" ]; then
      volumes+=("$(basename "$vol")")
    fi
  done
  if [ "${#volumes[@]}" -eq 0 ]; then
    log_error "未检测到任何卷。"
    return 1
  fi
  echo "$prompt"
  local i=1
  for vol in "${volumes[@]}"; do
    echo "$i) $vol"
    i=$((i+1))
  done
  read -p "请输入选项编号: " choice
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#volumes[@]}" ]; then
    log_error "无效的选择。"
    return 1
  fi
  echo "${volumes[$((choice-1))]}"
}

# 同时选择系统卷与数据卷（返回格式：系统卷###数据卷）
scan_and_select_volumes() {
  local boot_vol data_vol delim="###"
  boot_vol=$(select_volume "请选择系统卷:") || { log_error "选择系统卷失败。"; return 1; }
  data_vol=$(select_volume "请选择数据卷:") || { log_error "选择数据卷失败。"; return 1; }
  echo "${boot_vol}${delim}${data_vol}"
}

# ======================= 获取卷信息 =======================
# 自动检测卷名，并提供手动输入或卷扫描选择的方式
get_volumes() {
  local delim="###"
  local boot_vol data_vol
  boot_vol=$(diskutil info / | awk -F': ' '/Volume Name/ {print $2}' | head -n1 | xargs)
  data_vol=$(diskutil info /System/Volumes/Data | awk -F': ' '/Volume Name/ {print $2}' | head -n1 | xargs)
  
  printf "${BLU}自动检测到系统卷名称为：${CYAN}%s${NC}\n" "$boot_vol"
  printf "${BLU}自动检测到数据卷名称为：${CYAN}%s${NC}\n" "$data_vol"
  
  if [[ $NONINTERACTIVE -eq 0 ]]; then
    read -p "$(printf "${YEL}如信息正确，直接按 Enter；输入 'n' 以手动设置；输入 'm' 以进行卷扫描选择:${NC}")" confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
      printf "${YEL}请输入系统卷名称 (例如：Macintosh HD): ${NC}"
      read -r boot_vol
      printf "${YEL}请输入数据卷名称 (例如：Macintosh HD - Data 或 Data): ${NC}"
      read -r data_vol
    elif [[ "$confirm" =~ ^[Mm]$ ]]; then
      local volumes
      volumes=$(scan_and_select_volumes) || { log_error "卷扫描选择失败。"; return 1; }
      IFS="$delim" read -r boot_vol data_vol <<< "$volumes"
    fi
  else
    log_info "非交互模式下，使用自动检测到的卷名。"
  fi
  
  if [ ! -d "/Volumes/$boot_vol" ]; then
    log_error "找不到系统卷：/Volumes/$boot_vol"
    return 1
  fi
  if [ ! -d "/Volumes/$data_vol" ]; then
    log_error "找不到数据卷：/Volumes/$data_vol"
    return 1
  fi

  echo "${boot_vol}${delim}${data_vol}"
}

# ======================= 更新 hosts 文件规则函数 =======================
update_hosts_file() {
  local hosts_file=$1
  shift
  local domains=("$@")
  if [ -f "$hosts_file" ]; then
    # 创建备份（仅在第一次更新时创建）
    if [ ! -f "${hosts_file}.bak" ]; then
      cp "$hosts_file" "${hosts_file}.bak" && log_info "已备份 hosts 文件为 ${hosts_file}.bak"
    fi
  else
    log_error "找不到 hosts 文件：$hosts_file"
    return 1
  fi

  for domain in "${domains[@]}"; do
    if ! grep -q "$domain" "$hosts_file"; then
      echo "0.0.0.0 $domain" >> "$hosts_file" && log_info "已添加阻断规则：$domain" || log_warn "无法更新阻断规则：$domain"
    else
      log_warn "hosts 中已存在阻断规则：$domain"
    fi
  done
}

# ======================= 辅助函数 =======================
press_enter_to_continue() {
  if [[ $NONINTERACTIVE -eq 0 ]]; then
    printf "${BLU}按 Enter 键返回主菜单...${NC}\n"
    read -r
  fi
}

# ======================= 核心功能函数 =======================

# 恢复模式绕过：创建用户、更新 hosts、更新配置文件
autobypass_on_recovery() {
  log_info "开始执行恢复模式绕过操作..."
  local volumes delim boot_volume data_volume
  volumes=$(get_volumes) || { log_error "磁盘卷检测失败，无法继续。"; press_enter_to_continue; return 1; }
  delim="###"
  IFS="$delim" read -r boot_volume data_volume <<< "$volumes"

  # 询问是否将数据卷重命名为 "Data"
  if [ "$data_volume" != "Data" ]; then
    if [[ $NONINTERACTIVE -eq 0 ]]; then
      printf "${YEL}检测到数据卷名称为：%s，需要重命名为 'Data' 吗？(y/n)${NC}\n" "$data_volume"
      read -r rename_confirm
    else
      rename_confirm="y"
    fi
    if [[ "$rename_confirm" =~ ^[Yy]$ ]]; then
      if ! diskutil rename "$data_volume" "Data"; then
        log_error "重命名数据卷失败，终止操作。"
        press_enter_to_continue
        return 1
      fi
      data_volume="Data"
      log_info "数据卷已重命名为 'Data'."
    else
      log_warn "用户选择不重命名数据卷，将使用原名称：$data_volume"
    fi
  fi

  # 尝试确定 dscl 数据库路径
  local dscl_path
  dscl_path="/Volumes/$data_volume/private/var/db/dslocal/nodes/Default"
  if [ ! -d "$dscl_path" ]; then
    log_warn "数据卷的 dscl 路径不存在，尝试使用系统卷路径。"
    dscl_path="/Volumes/$boot_volume/private/var/db/dslocal/nodes/Default"
    if [ ! -d "$dscl_path" ]; then
      log_error "无法找到目录服务数据库路径：$dscl_path"
      press_enter_to_continue
      return 1
    fi
    log_info "使用系统卷的 dscl_path: $dscl_path"
  fi

  # 用户创建（全名与用户名均默认为 "Apple"）
  printf "${BLU}请输入新用户信息（回车使用默认值）：${NC}\n"
  if [[ $NONINTERACTIVE -eq 0 ]]; then
    read -p "$(printf "${YEL}用户全名 (默认: Apple): ${NC}")" realName
  else
    realName="Apple"
    log_info "非交互模式下，使用默认用户全名：Apple"
  fi
  realName="${realName:-Apple}"

  if [[ $NONINTERACTIVE -eq 0 ]]; then
    read -p "$(printf "${YEL}用户名 (默认: Apple, 请勿包含空格): ${NC}")" username
  else
    username="Apple"
    log_info "非交互模式下，使用默认用户名：Apple"
  fi
  username="${username:-Apple}"

  if dscl -f "$dscl_path" . -read "/Users/$username" &>/dev/null; then
    log_warn "用户 $username 已存在，跳过用户创建。"
  else
    if [[ $NONINTERACTIVE -eq 0 ]]; then
      read -s -p "$(printf "${YEL}密码 (默认: 1234): ${NC}")" passw
      echo ""
    else
      passw="1234"
      log_info "非交互模式下，使用默认密码。"
    fi
    passw="${passw:-1234}"

    # 动态分配 UID 避免冲突
    local uid=501 existing_uids
    existing_uids=$(dscl -f "$dscl_path" . -list /Users UniqueID | awk '{print $2}')
    while echo "$existing_uids" | grep -qw "$uid"; do
      uid=$((uid + 1))
    done
    log_info "将为 $username 分配 UID: $uid"

    if ! dscl -f "$dscl_path" . -create "/Users/$username"; then
      log_error "创建用户失败！"
      press_enter_to_continue
      return 1
    fi
    dscl -f "$dscl_path" . -create "/Users/$username" UserShell "/bin/zsh"
    dscl -f "$dscl_path" . -create "/Users/$username" RealName "$realName"
    dscl -f "$dscl_path" . -create "/Users/$username" UniqueID "$uid"
    dscl -f "$dscl_path" . -create "/Users/$username" PrimaryGroupID "20"
    dscl -f "$dscl_path" . -create "/Users/$username" NFSHomeDirectory "/Users/$username"
    dscl -f "$dscl_path" . -passwd "/Users/$username" "$passw"
    dscl -f "$dscl_path" . -append "/Groups/admin" GroupMembership "$username"
    log_info "用户 $username 创建成功。"

    local user_home="/Volumes/$data_volume/Users/$username"
    if [ ! -d "$user_home" ]; then
      if mkdir -p "$user_home"; then
        log_info "已创建用户主目录：$user_home"
      else
        log_error "无法创建用户主目录：$user_home"
      fi
    fi
  fi

  # 修改 hosts 文件，屏蔽 MDM 域名
  local hosts_file="/Volumes/$boot_volume/etc/hosts"
  update_hosts_file "$hosts_file" "deviceenrollment.apple.com" "mdmenrollment.apple.com" "iprofiles.apple.com"

  # 更新 MDM 配置文件
  local config_dir="/Volumes/$boot_volume/var/db/ConfigurationProfiles/Settings"
  if [ -d "$config_dir" ]; then
    touch "$config_dir/.cloudConfigProfileInstalled" "$config_dir/.cloudConfigRecordNotFound"
    rm -f "$config_dir/.cloudConfigHasActivationRecord" "$config_dir/.cloudConfigRecordFound"
    log_info "MDM 配置文件已更新。"
  else
    log_error "配置目录不存在：$config_dir"
  fi

  # 创建 .AppleSetupDone 文件以跳过初始设置
  local setup_done_file="/Volumes/$data_volume/private/var/db/.AppleSetupDone"
  if touch "$setup_done_file"; then
    log_info "已创建 .AppleSetupDone 文件，将跳过初始设置。"
  else
    log_error "无法创建 .AppleSetupDone 文件：$setup_done_file"
  fi

  printf "${CYAN}*-------- Autobypass 已完成 --------*${NC}\n"
  printf "${CYAN}*------ 请退出终端并重启 Mac ------*${NC}\n"
  press_enter_to_continue
}

# 统一停用通知函数（根据环境自动选择配置路径）
disable_notification() {
  log_info "执行停用通知操作..."
  local config_dir=""
  if [ -d "/var/db/ConfigurationProfiles/Settings" ]; then
    config_dir="/var/db/ConfigurationProfiles/Settings"
    log_info "检测到 SIP 模式下的通知配置目录，正在执行操作..."
  else
    local volumes delim boot_volume data_volume
    volumes=$(get_volumes) || { log_error "无法获取磁盘卷信息。"; press_enter_to_continue; return 1; }
    delim="###"
    IFS="$delim" read -r boot_volume data_volume <<< "$volumes"
    config_dir="/Volumes/$boot_volume/var/db/ConfigurationProfiles/Settings"
    log_info "检测到恢复模式下的通知配置目录，正在执行操作..."
  fi
  rm -f "$config_dir/.cloudConfigHasActivationRecord" "$config_dir/.cloudConfigRecordFound"
  touch "$config_dir/.cloudConfigProfileInstalled" "$config_dir/.cloudConfigRecordNotFound"
  log_info "通知已成功停用。"
  press_enter_to_continue
}

check_mdm_enrollment() {
  log_info "检查 MDM 注册状态..."
  if profiles show -type enrollment; then
    log_info "已显示 MDM 注册状态。"
  else
    log_error "无法检索 MDM 注册状态。可能在 Recovery 下不可用或未安装 profiles。"
  fi
  press_enter_to_continue
}

reboot_system() {
  log_warn "即将重启系统..."
  if [[ $NONINTERACTIVE -eq 0 ]]; then
    read -p "确认重启？(y/n): " confirm
  else
    confirm="y"
  fi
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    reboot
  else
    log_info "已取消重启。"
  fi
  press_enter_to_continue
}

block_mdm_service() {
  log_info "执行屏蔽 MDM 服务操作..."
  local volumes delim boot_volume data_volume
  volumes=$(get_volumes) || { log_error "无法获取卷信息，无法继续屏蔽 MDM 服务。"; press_enter_to_continue; return 1; }
  delim="###"
  IFS="$delim" read -r boot_volume data_volume <<< "$volumes"

  # 备份并禁用 mdmclient
  local mdmclient_path="/Volumes/$boot_volume/usr/libexec/mdmclient"
  if [ -f "$mdmclient_path" ]; then
    if [ ! -f "${mdmclient_path}.bak" ]; then
      cp "$mdmclient_path" "${mdmclient_path}.bak" && log_info "已备份 mdmclient 为 ${mdmclient_path}.bak"
    fi
    if mv "$mdmclient_path" "${mdmclient_path}.disabled"; then
      log_info "已禁用 mdmclient."
    else
      log_warn "无法禁用 mdmclient。"
    fi
  else
    log_warn "未找到 mdmclient，跳过禁用。"
  fi

  # 备份并禁用 MDM 启动项 plist
  local mdm_daemon="/Volumes/$boot_volume/System/Library/LaunchDaemons/com.apple.mdmclient.plist"
  if [ -f "$mdm_daemon" ]; then
    if [ ! -f "${mdm_daemon}.bak" ]; then
      cp "$mdm_daemon" "${mdm_daemon}.bak" && log_info "已备份 MDM 启动项为 ${mdm_daemon}.bak"
    fi
    if mv "$mdm_daemon" "${mdm_daemon}.disabled"; then
      log_info "已禁用 MDM 启动项。"
    else
      log_warn "无法禁用 MDM 启动项。"
    fi
  else
    log_warn "未找到 MDM 启动项 plist，跳过禁用。"
  fi

  local hosts_file="/Volumes/$boot_volume/etc/hosts"
  update_hosts_file "$hosts_file" "deviceenrollment.apple.com" "mdmenrollment.apple.com" "iprofiles.apple.com" "mdm.apple.com"

  log_info "MDM 服务屏蔽操作完成。"
  press_enter_to_continue
}

# ======================= 一次性执行所有操作函数 =======================
solve_all() {
  log_info "开始一次性执行所有操作..."
  SKIP_WAIT=1
  set +e
  autobypass_on_recovery || log_warn "执行 autobypass_on_recovery 过程中出现错误，继续下一步。"
  disable_notification || log_warn "执行 disable_notification 过程中出现错误，继续下一步。"
  block_mdm_service || log_warn "执行 block_mdm_service 过程中出现错误，继续下一步。"
  check_mdm_enrollment || log_warn "执行 check_mdm_enrollment 过程中出现错误。"
  set -euo pipefail
  log_info "一次性操作全部执行完毕，请检查日志确认状态。"
  unset SKIP_WAIT
  press_enter_to_continue
}

# ======================= 参数解析 =======================
if [ "$#" -gt 0 ]; then
  case "$1" in
    autobypass)
      check_dependency
      check_root
      check_recovery_mode
      autobypass_on_recovery
      exit 0
      ;;
    disable_notification)
      check_dependency
      check_root
      disable_notification
      exit 0
      ;;
    check_mdm)
      check_dependency
      check_root
      check_mdm_enrollment
      exit 0
      ;;
    reboot)
      check_dependency
      check_root
      reboot_system
      exit 0
      ;;
    block_mdm)
      check_dependency
      check_root
      block_mdm_service
      exit 0
      ;;
    solve_all)
      check_dependency
      check_root
      check_recovery_mode
      solve_all
      exit 0
      ;;
    manual)
      show_manual
      exit 0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_error "无效的参数: $1"
      usage
      exit 1
      ;;
  esac
fi

# ======================= 交互式菜单 =======================
print_banner() {
  if command -v clear >/dev/null 2>&1; then
    clear
  else
    printf "\033c"
  fi
  printf "${CYAN}*------------------------------*------------------------------*${NC}\n"
  printf "${RED}   MDM Skipper - BX-E.COM | BXTE STUDIO${NC}\n"
  printf "${CYAN}*------------------------------*------------------------------*${NC}\n\n"
}

show_menu() {
  printf "${PUR}请选择要执行的操作:${NC}\n"
  printf "1) 自动绕过恢复模式 - Autobypass on Recovery\n"
  printf "2) 停用通知 - Disable Notification\n"
  printf "3) 检查 MDM 注册状态 - Check MDM Enrollment\n"
  printf "4) 重启系统 - Reboot\n"
  printf "5) 屏蔽 MDM 服务 - Block MDM Service\n"
  printf "6) 一次性执行所有操作 - Solve All\n"
  printf "7) 用户手册 - Show Manual\n"
  printf "8) 退出 - Exit\n\n"
}

# ======================= 主程序入口 =======================
print_banner
check_dependency
check_root
check_recovery_mode

while true; do
  show_menu
  read -p "$(printf "${BLU}请输入选项 [1-8]: ${NC}")" choice
  case "$choice" in
    1) autobypass_on_recovery ;;
    2) disable_notification ;;
    3) check_mdm_enrollment ;;
    4) reboot_system ;;
    5) block_mdm_service ;;
    6) solve_all ;;
    7) show_manual ;;
    8)
       log_info "感谢使用，本程序将退出。"
       break
       ;;
    *)
       log_error "无效的选项：$choice"
       press_enter_to_continue
       ;;
  esac
done
