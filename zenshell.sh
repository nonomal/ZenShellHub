#!/bin/bash
# ========================================================
# ZenShell Hub - CLI Client
# 极简、高颜值的终端脚本管理客户端
# ========================================================

# --- 全局配置 ---
CONFIG_FILE="$HOME/.zenshell_config"
CACHE_FILE="/tmp/zenshell_cache.json"

# --- 颜色定义 (Zen Style) ---
C_RESET='\033[0m'
C_CYAN='\033[1;36m'
C_BLUE='\033[1;34m'
C_GREEN='\033[1;32m'
C_GRAY='\033[1;30m'
C_WHITE='\033[1;37m'
C_RED='\033[1;31m'
C_BG='\033[44m' # 蓝色背景用于高亮

# --- 工具函数 ---

# 打印头部 LOGO
print_header() {
    clear
    echo -e "${C_CYAN}"
    echo "  Zen Shell Hub 🐚 CLI"
    echo -e "${C_GRAY}  https://github.com/wang4386/zenshellhub"
    echo -e "${C_GRAY}  ====================${C_RESET}"
    echo ""
}

# 检查依赖
check_deps() {
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${C_RED}[Error] 需要 curl 工具。${C_RESET}"
        exit 1
    fi
    # 优先使用 python3 处理 JSON，因为大多数系统自带且比 shell 字符串处理更稳健
    if ! command -v python3 >/dev/null 2>&1; then
        echo -e "${C_RED}[Error] 需要 python3 来解析 JSON 数据。${C_RESET}"
        exit 1
    fi
}

# 首次运行设置向导
setup_wizard() {
    print_header
    echo -e "${C_WHITE}欢迎首次使用 ZenShell Hub。${C_RESET}"
    echo -e "${C_GRAY}我们需要配置您的服务端连接信息。${C_RESET}\n"

    # 1. 输入端点
    while true; do
        read -p "$(echo -e "${C_CYAN}请输入对接端点 (URL) [例如 http://myserver.com/]: ${C_RESET}")" INPUT_URL
        # 去除末尾斜杠
        INPUT_URL=${INPUT_URL%/}
        
        if [[ "$INPUT_URL" =~ ^http ]]; then
            break
        else
            echo -e "${C_RED}格式错误: URL 必须以 http 或 https 开头。${C_RESET}"
        fi
    done

    # 2. 输入密码
    echo ""
    read -s -p "$(echo -e "${C_CYAN}请输入管理员密码: ${C_RESET}")" INPUT_PASS
    echo ""

    # 3. 验证连接
    echo -e "\n${C_GRAY}正在验证连接...${C_RESET}"
    
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "{\"password\":\"$INPUT_PASS\"}" \
        "$INPUT_URL?action=verify_password")

    if [ "$HTTP_STATUS" == "200" ]; then
        echo -e "${C_GREEN}√ 验证成功！${C_RESET}"
        
        # 写入配置
        echo "ZEN_URL=\"$INPUT_URL\"" > "$CONFIG_FILE"
        # 简单的 Base64 混淆存储密码（仅防君子）
        echo "ZEN_PASS=\"$(echo -n "$INPUT_PASS" | base64)\"" >> "$CONFIG_FILE"

        # 4. 创建快捷指令
        install_alias
    else
        echo -e "${C_RED}× 验证失败 (HTTP $HTTP_STATUS)。请检查 URL 或密码。${C_RESET}"
        exit 1
    fi
}

# 安装 Shell 快捷别名
install_alias() {
    SHELL_RC=""
    case "$SHELL" in
        */zsh) SHELL_RC="$HOME/.zshrc" ;;
        */bash) SHELL_RC="$HOME/.bashrc" ;;
        *) ;;
    esac

    SCRIPT_PATH=$(realpath "$0")
    ALIAS_CMD="alias zensh='bash $SCRIPT_PATH'"

    if [ -n "$SHELL_RC" ]; then
        if ! grep -q "alias zensh=" "$SHELL_RC"; then
            echo "" >> "$SHELL_RC"
            echo "# ZenShell Hub Shortcut" >> "$SHELL_RC"
            echo "$ALIAS_CMD" >> "$SHELL_RC"
            echo -e "${C_GREEN}√ 已向 $SHELL_RC 添加快捷指令 'zensh'${C_RESET}"
            echo -e "${C_GRAY}  (提示: 为防止冲突，我们使用了 'zensh' 而非 'zsh')${C_RESET}"
            echo -e "${C_WHITE}请运行 ${C_CYAN}source $SHELL_RC${C_WHITE} 或重启终端以生效。${C_RESET}"
            echo -e "之后您可以直接输入 ${C_CYAN}zensh${C_RESET} 进入脚本中心。"
            read -p "按回车继续..."
        fi
    fi
}

# 卸载功能
uninstall() {
    print_header
    echo -e "${C_RED}=== 卸载 ZenShell Hub CLI ===${C_RESET}"
    echo -e "${C_GRAY}此操作将执行以下内容：${C_RESET}"
    echo -e "1. 删除配置文件 ($CONFIG_FILE)"
    echo -e "2. 删除本地缓存 ($CACHE_FILE)"
    echo -e "3. 尝试从 Shell 配置文件中移除 'zensh' 别名"
    echo -e "4. 删除脚本文件自身 ($0)"
    echo ""
    read -p "确认要继续卸载吗? [y/N] " CONFIRM
    
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        return
    fi

    echo ""
    # 1. Remove Config
    if [ -f "$CONFIG_FILE" ]; then
        rm -f "$CONFIG_FILE"
        echo -e "${C_GRAY}- 已删除配置文件${C_RESET}"
    fi

    # 2. Remove Cache
    if [ -f "$CACHE_FILE" ]; then
        rm -f "$CACHE_FILE"
        echo -e "${C_GRAY}- 已删除缓存文件${C_RESET}"
    fi

    # 3. Remove Alias
    SHELL_RC=""
    case "$SHELL" in
        */zsh) SHELL_RC="$HOME/.zshrc" ;;
        */bash) SHELL_RC="$HOME/.bashrc" ;;
    esac

    if [ -n "$SHELL_RC" ] && [ -f "$SHELL_RC" ]; then
        # 简单备份
        cp "$SHELL_RC" "${SHELL_RC}.zen_bak"
        
        # 尝试移除包含 alias zensh= 的行和它的注释
        # 使用 grep -v 反向过滤生成临时文件，然后覆盖
        grep -v "alias zensh=" "$SHELL_RC" | grep -v "# ZenShell Hub Shortcut" > "${SHELL_RC}.tmp" && mv "${SHELL_RC}.tmp" "$SHELL_RC"
        
        echo -e "${C_GRAY}- 已从 $SHELL_RC 清理别名 (备份位于 ${SHELL_RC}.zen_bak)${C_RESET}"
        echo -e "${C_GRAY}  (提示: 请重新打开终端或运行 source $SHELL_RC 使变更生效)${C_RESET}"
    fi

    # 4. Remove Self
    SCRIPT_PATH=$(realpath "$0")
    echo -e "${C_GRAY}- 正在自毁...${C_RESET}"
    rm -f "$SCRIPT_PATH"
    
    echo -e "\n${C_GREEN}卸载完成。再见！${C_RESET}"
    exit 0
}

# Python 脚本：用于美观打印 JSON 列表
# 参数1: JSON 文件路径
py_list_scripts() {
python3 -c "
import sys, json

try:
    with open('$1', 'r') as f:
        data = json.load(f)
    
    if not data:
        print('EMPTY')
        sys.exit(0)

    # 打印表头
    print(f'{chr(27)}[1;30m{str(0).ljust(4)} | {chr(27)}[1;37mQUIT (退出){chr(27)}[0m')
    print(f'{chr(27)}[1;30mu    | {chr(27)}[1;31mUNINSTALL (卸载){chr(27)}[0m')
    print(f'{chr(27)}[1;30m---- + ----------------------------------------{chr(27)}[0m')

    for i, script in enumerate(data):
        idx = i + 1
        title = script.get('title', '无标题')
        desc = script.get('description', '')
        tags = script.get('tags', [])
        
        # 格式化输出
        tag_str = ' '.join([f'#{t}' for t in tags])
        if tag_str: tag_str = f' {chr(27)}[1;34m{tag_str}{chr(27)}[0m'
        
        print(f'{chr(27)}[1;36m{str(idx).ljust(4)}{chr(27)}[0m | {chr(27)}[1;37m{title}{chr(27)}[0m{tag_str}')
        if desc:
            # 截断过长的描述
            short_desc = (desc[:50] + '..') if len(desc) > 50 else desc
            print(f'     | {chr(27)}[0;90m{short_desc}{chr(27)}[0m')
            
except Exception as e:
    print('ERROR')
"
}

# Python 脚本：获取指定索引的命令
# 参数1: JSON 文件路径, 参数2: 索引 (1-based)
py_get_command() {
python3 -c "
import sys, json
try:
    with open('$1', 'r') as f:
        data = json.load(f)
    idx = int('$2') - 1
    if 0 <= idx < len(data):
        print(json.dumps(data[idx]))
    else:
        print('NULL')
except:
    print('NULL')
"
}

# --- 主程序逻辑 ---

check_deps

# 1. 配置加载
if [ ! -f "$CONFIG_FILE" ]; then
    setup_wizard
fi

source "$CONFIG_FILE"
PASS_DECODED=$(echo "$ZEN_PASS" | base64 -d)

# 2. 交互循环
while true; do
    print_header
    
    # 获取数据
    echo -e "${C_GRAY}正在从 $ZEN_URL 获取脚本列表...${C_RESET}"
    curl -s "$ZEN_URL?action=get_data" > "$CACHE_FILE"
    
    # 检查获取是否成功
    if [ ! -s "$CACHE_FILE" ] || grep -q "error" "$CACHE_FILE"; then
        echo -e "${C_RED}获取数据失败，请检查网络或服务端状态。${C_RESET}"
        read -p "按回车重试，或 Ctrl+C 退出..."
        continue
    fi

    echo ""
    # 调用 Python 渲染列表
    LIST_RESULT=$(py_list_scripts "$CACHE_FILE")
    
    if [ "$LIST_RESULT" == "EMPTY" ]; then
        echo -e "${C_WHITE}暂无收藏的脚本。${C_RESET}"
    elif [ "$LIST_RESULT" == "ERROR" ]; then
        echo -e "${C_RED}数据解析错误。${C_RESET}"
    else
        echo "$LIST_RESULT"
    fi

    echo ""
    echo -e "${C_GRAY}----------------------------------------${C_RESET}"
    read -p "$(echo -e "${C_CYAN}请输入序号执行脚本 > ${C_RESET}")" CHOICE

    # 退出逻辑
    if [ "$CHOICE" == "0" ] || [ -z "$CHOICE" ]; then
        echo "Bye!"
        exit 0
    fi

    # 卸载逻辑
    if [ "$CHOICE" == "u" ] || [ "$CHOICE" == "U" ]; then
        uninstall
        continue
    fi

    # 获取选中的脚本详情
    SCRIPT_JSON=$(py_get_command "$CACHE_FILE" "$CHOICE")

    if [ "$SCRIPT_JSON" == "NULL" ]; then
        echo -e "${C_RED}无效的序号。${C_RESET}"
        sleep 1
    else
        # 解析具体的字段
        SCRIPT_TITLE=$(echo "$SCRIPT_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['title'])")
        SCRIPT_CMD=$(echo "$SCRIPT_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['command'])")
        
        print_header
        echo -e "${C_GREEN}已选择: $SCRIPT_TITLE${C_RESET}"
        echo -e "${C_GRAY}即将执行以下命令:${C_RESET}\n"
        
        echo -e "${C_WHITE}----------------------------------------${C_RESET}"
        echo -e "${C_BLUE}${SCRIPT_CMD}${C_RESET}"
        echo -e "${C_WHITE}----------------------------------------${C_RESET}"
        echo ""
        
        read -p "$(echo -e "确认执行? [Y/n] ")" CONFIRM
        if [[ -z "$CONFIRM" || "$CONFIRM" =~ ^[Yy]$ ]]; then
            echo ""
            echo -e "${C_GRAY}--- Output Start ---${C_RESET}"
            # 真正执行命令
            eval "$SCRIPT_CMD"
            echo -e "${C_GRAY}--- Output End ---${C_RESET}"
            echo ""
            read -p "按回车返回列表..."
        fi
    fi
done