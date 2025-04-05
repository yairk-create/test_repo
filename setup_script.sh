#!/bin/bash
# Automated Package Installation and Vim Setup Script with OS Detection (Semaphore Compatible)

# Define main paths
HOME_DIR="$HOME"
LOG_DIR="$HOME_DIR/logs"
LOG_FILE="$LOG_DIR/auto_config.log"
SECRET_DIR="$HOME_DIR/project"
SECRET_FILE="$SECRET_DIR/.secret"

# Set strict error handling
set -uo pipefail

# Logging function
function log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_message="[$timestamp][$level] $message"
    
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "$log_message" >> "$LOG_FILE"
    
    case "$level" in
        "INFO")
            echo -e "\033[0;32m$log_message\033[0m"
            ;;
        "WARNING")
            echo -e "\033[0;33m$log_message\033[0m"
            ;;
        "ERROR")
            echo -e "\033[0;31m$log_message\033[0m"
            ;;
        *)
            echo "$log_message"
            ;;
    esac
}

# Detect OS function
function detect_os() {
    # Default values
    PKG_MANAGER=""
    INSTALL_CMD=""
    UPDATE_CMD=""
    
    if [ -f /etc/os-release ]; then
        # freedesktop.org and systemd
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        # linuxbase.org
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        # For some versions of Debian/Ubuntu without lsb_release command
        . /etc/lsb-release
        OS=$DISTRIB_ID
        VER=$DISTRIB_RELEASE
    elif [ -f /etc/debian_version ]; then
        # Older Debian/Ubuntu/etc.
        OS=Debian
        VER=$(cat /etc/debian_version)
    elif [ -f /etc/centos-release ]; then
        OS=CentOS
        VER=$(cat /etc/centos-release | sed 's/.*release \([0-9]\).*/\1/')
    elif [ -f /etc/redhat-release ]; then
        # Older Red Hat, CentOS, etc.
        if grep -q "Rocky Linux" /etc/redhat-release; then
            OS="Rocky Linux"
            VER=$(cat /etc/redhat-release | sed 's/.*release \([0-9]\).*/\1/')
        else
            OS=RedHat
            VER=$(cat /etc/redhat-release | sed 's/.*release \([0-9]\).*/\1/')
        fi
    elif [ "$(uname)" = "Darwin" ]; then
        # macOS
        OS="macOS"
        VER=$(sw_vers -productVersion)
    else
        # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
        OS=$(uname -s)
        VER=$(uname -r)
    fi

    log "INFO" "Detected OS: $OS $VER"
    
    # Determine package manager based on OS
    if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]] || [[ "$OS" == *"Linux Mint"* ]]; then
        PKG_MANAGER="apt-get"
        INSTALL_CMD="install -y"
        UPDATE_CMD="update"
    elif [[ "$OS" == *"Rocky"* ]] || [[ "$OS" == *"CentOS"* ]] && [[ "$VER" == "8"* ]]; then
        PKG_MANAGER="dnf"
        INSTALL_CMD="install -y"
        UPDATE_CMD="check-update || true"  # Returns 100 if updates are available
    elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"RedHat"* ]]; then
        PKG_MANAGER="yum"
        INSTALL_CMD="install -y"
        UPDATE_CMD="update -y"
    elif [[ "$OS" == *"Fedora"* ]]; then
        PKG_MANAGER="dnf"
        INSTALL_CMD="install -y"
        UPDATE_CMD="check-update || true"
    elif [[ "$OS" == *"Arch"* ]] || [[ "$OS" == *"Manjaro"* ]]; then
        PKG_MANAGER="pacman"
        INSTALL_CMD="-S --noconfirm"
        UPDATE_CMD="-Syu --noconfirm"
    elif [[ "$OS" == *"SUSE"* ]]; then
        PKG_MANAGER="zypper"
        INSTALL_CMD="install -y"
        UPDATE_CMD="refresh"
    elif [[ "$OS" == "macOS" ]]; then
        if command -v brew >/dev/null 2>&1; then
            PKG_MANAGER="brew"
            INSTALL_CMD="install"
            UPDATE_CMD="update"
        else
            log "ERROR" "Homebrew not found on macOS. Please install Homebrew first."
            return 1
        fi
    else
        log "ERROR" "Unsupported OS: $OS"
        return 1
    fi
    
    log "INFO" "Using package manager: $PKG_MANAGER with install command: $INSTALL_CMD"
    return 0
}

# Setup initial environment
function setup_environment() {
    mkdir -p "$LOG_DIR" "$SECRET_DIR"
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    log "INFO" "Environment setup completed"
}

# Setup permissions for Ansible
function setup_permissions() {
    log "INFO" "Running with Ansible - sudo access should be pre-configured"
    
    # Create a placeholder file
    touch "$SECRET_FILE"
    chmod 600 "$SECRET_FILE"
    echo "ansible-managed" > "$SECRET_FILE"
    
    # Test sudo access
    if sudo -n true 2>/dev/null; then
        log "INFO" "Sudo access verified"
    else
        log "WARNING" "This script expects passwordless sudo via Ansible"
        log "INFO" "Continuing execution assuming Ansible is handling sudo credentials"
    fi
    
    return 0
}

# Map package names for different package managers
function map_package_name() {
    local generic_name="$1"
    local mapped_name="$generic_name"
    
    case "$PKG_MANAGER" in
        "apt-get")
            case "$generic_name" in
                "python") mapped_name="python3" ;;
                "pip") mapped_name="python3-pip" ;;
            esac
            ;;
        "yum"|"dnf")
            case "$generic_name" in
                "vim-nox") mapped_name="vim-enhanced" ;;
                "python") mapped_name="python3" ;;
                "pip") mapped_name="python3-pip" ;;
            esac
            ;;
        "pacman")
            case "$generic_name" in
                "vim-nox") mapped_name="vim" ;;
                "python") mapped_name="python" ;;
                "pip") mapped_name="python-pip" ;;
            esac
            ;;
        "brew")
            case "$generic_name" in
                "vim-nox") mapped_name="vim" ;;
                "net-tools") mapped_name="inetutils" ;;
                "python") mapped_name="python" ;;
                "pip") return 1 ;; # Skip pip, comes with python
                "ssh") return 1 ;; # Skip ssh, macOS has it built-in
            esac
            ;;
    esac
    
    echo "$mapped_name"
    return 0
}

# Setup Vim configuration
function setup_vim() {
    log "INFO" "Setting up Vim configuration..."
    
    # Create vim autoload directory and install vim-plug
    local vim_autoload_dir="$HOME/.vim/autoload"
    mkdir -p "$vim_autoload_dir"
    
    if ! curl -fLo "$vim_autoload_dir/plug.vim" --create-dirs \
        https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim; then
        log "ERROR" "Failed to install vim-plug"
        return 1
    fi
    
    # Create .vimrc
    cat > "$HOME/.vimrc" << 'EOL'
" Vim-Plug Configuration
call plug#begin()

" Plugins
Plug 'sheerun/vim-polyglot'
Plug 'preservim/nerdtree', { 'on': 'NERDTreeToggle' }
Plug 'LunarWatcher/auto-pairs'
Plug 'maxboisvert/vim-simple-complete'
Plug 'liuchengxu/space-vim-dark'
Plug 'godlygeek/tabular'
Plug 'preservim/vim-markdown'
Plug 'tpope/vim-fugitive'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'tomasr/molokai'
Plug 'sainnhe/sonokai'
Plug 'mg979/vim-visual-multi', {'branch': 'master'}
Plug 'sillybun/vim-repl'

call plug#end()

" Basic Settings
syntax enable
set number
set relativenumber
set expandtab
set tabstop=4
set shiftwidth=4
set autoindent
set smartindent
set cursorline
set showmatch
set incsearch
set hlsearch
set ignorecase
set smartcase
set wrap
set linebreak
set showcmd
set showmode
set history=1000
set wildmenu
set wildmode=list:longest
set mouse=a

" Color scheme
colorscheme desert
if has('termguicolors')
    set termguicolors
    try
        colorscheme sonokai
    catch
        try
            colorscheme molokai
        catch
        endtry
    endtry
endif

" Key mappings
nnoremap <C-n> :NERDTreeToggle<CR>
let g:airline_powerline_fonts = 1
let g:airline_theme='sonokai'

" Custom functions
function! ToggleLineNumbers()
    if(&relativenumber == 1)
        set norelativenumber
        set nonumber
    else
        set relativenumber
        set number
    endif
endfunction

" Custom keymaps
nnoremap <F2> :call ToggleLineNumbers()<CR>
EOL

    # For macOS, add specific settings
    if [[ "$OS" == "macOS" ]]; then
        cat >> "$HOME/.vimrc" << 'EOL'

" macOS specific settings
if has("mac")
    set clipboard=unnamed
    " Fix backspace
    set backspace=indent,eol,start
endif
EOL
    fi

    log "INFO" "Installing Vim plugins..."
    if ! vim +PlugInstall +qall; then
        log "WARNING" "Some plugins might have failed to install"
    fi
    
    log "INFO" "Vim setup completed"
    return 0
}

# Install additional tools for specific OS
function install_os_specific_tools() {
    if [[ "$OS" == "macOS" ]]; then
        log "INFO" "Installing macOS specific tools..."
        brew install coreutils findutils gnu-tar gnu-sed gawk gnutls grep || log "WARNING" "Some macOS-specific tools failed to install"
    elif [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
        log "INFO" "Installing additional tools for Debian/Ubuntu..."
        sudo apt-get install -y software-properties-common build-essential || log "WARNING" "Failed to install some Debian/Ubuntu specific tools"
    elif [[ "$OS" == *"Rocky"* ]]; then
        log "INFO" "Installing additional tools for Rocky Linux..."
        sudo dnf install -y epel-release || log "WARNING" "Failed to install EPEL repository"
        sudo dnf group install -y "Development Tools" || log "WARNING" "Failed to install development tools"
    elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"RedHat"* ]] || [[ "$OS" == *"Fedora"* ]]; then
        log "INFO" "Installing additional tools for RHEL/CentOS/Fedora..."
        if [[ "$PKG_MANAGER" == "dnf" ]]; then
            sudo dnf install -y epel-release || log "WARNING" "Failed to install EPEL repository"
            sudo dnf group install -y "Development Tools" || log "WARNING" "Failed to install development tools"
        else
            sudo yum install -y epel-release || log "WARNING" "Failed to install EPEL repository"
            sudo yum groupinstall -y "Development Tools" || log "WARNING" "Failed to install development tools"
        fi
    fi
}

# Main package installation function
function install_packages() {
    local base_packages=(
        vim-nox
        htop
        curl
        git
        ssh
        net-tools
        wget
        tmux
        nmap
        tree
        neofetch
        iftop
        ncdu
        nodejs
        python
        pip
    )
    
    local packages_to_install=()
    
    log "INFO" "Starting package installation process"
    
    # Update package manager
    log "INFO" "Updating package repositories..."
    if [[ "$PKG_MANAGER" == "brew" ]]; then
        $PKG_MANAGER $UPDATE_CMD || log "WARNING" "Failed to update Homebrew"
    else
        sudo $PKG_MANAGER $UPDATE_CMD || log "WARNING" "Failed to update package repositories"
    fi
    
    # Map and filter packages for the specific OS
    for pkg in "${base_packages[@]}"; do
        mapped_pkg=$(map_package_name "$pkg")
        if [ $? -eq 0 ]; then
            packages_to_install+=("$mapped_pkg")
        fi
    done
    
    # Install packages
    log "INFO" "Installing packages: ${packages_to_install[*]}"
    if [[ "$PKG_MANAGER" == "brew" ]]; then
        for pkg in "${packages_to_install[@]}"; do
            log "INFO" "Installing $pkg..."
            $PKG_MANAGER $INSTALL_CMD "$pkg" || log "WARNING" "Failed to install $pkg"
        done
    else
        sudo $PKG_MANAGER $INSTALL_CMD ${packages_to_install[@]} || {
            log "ERROR" "Failed to install packages"
            return 1
        }
    fi
    
    # Install OS-specific additional tools
    install_os_specific_tools
    
    # Setup Vim after package installation
    if ! setup_vim; then
        log "WARNING" "Vim setup encountered issues"
    fi
    
    log "INFO" "All packages installed successfully"
    return 0
}

# Cleanup function
function cleanup() {
    log "INFO" "Performing cleanup..."
    if [[ -f "$SECRET_FILE" ]]; then
        rm -f "$SECRET_FILE"
        log "INFO" "Removed password file"
    fi
}

# Main execution
function main() {
    if ! setup_environment; then
        echo "Failed to set up environment"
        exit 1
    fi
    
    if ! detect_os; then
        log "ERROR" "Failed to detect OS"
        exit 1
    fi
    
    if ! setup_permissions; then
        log "ERROR" "Failed to set up permissions"
        exit 1
    fi
    
    if ! install_packages; then
        log "ERROR" "Package installation failed"
        cleanup
        exit 1
    fi
    
    cleanup
    log "INFO" "Script completed successfully"
}

# Execute main function
main
