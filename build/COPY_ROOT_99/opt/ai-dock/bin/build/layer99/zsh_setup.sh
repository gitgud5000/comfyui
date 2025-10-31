readonly ZSH_CUSTOM="${USER_HOME}/.oh-my-zsh/custom"
# Refresh APT index (it may have been cleaned in previous layers) and install
sudo apt-get update
sudo apt-get install -y --no-install-recommends zsh

USER="root"

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }


setup_zsh() {
	log_info "Setting up Zsh and Oh My Zsh..."
	
	# Install Oh My Zsh non-interactively
	sudo -u ${USER} -i bash <<- 'EOF'
	export RUNZSH=no
	export CHSH=no
	export KEEP_ZSHRC=yes
	sh -c "$(wget -q https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -O -)"
	EOF
	
	# Change default shell to zsh
	sudo chsh -s $(which zsh) $USER
	# sudo chsh -s $(which zsh) azureuser
	
	log_success "Oh My Zsh installed successfully"
	#TODO:mayberemove
	printf "cd %s\n" "$WORKSPACE" >> /root/.zshrc
}

install_zsh_plugins() {
	log_info "Installing Zsh plugins and themes..."

	sudo -u ${USER} bash <<-'EOF'
	# Create plugins directory
	mkdir -p ~/.oh-my-zsh/custom/plugins
	mkdir -p ~/.oh-my-zsh/custom/themes

	# Install theme
	git clone --quiet https://github.com/romkatv/powerlevel10k.git ~/.oh-my-zsh/custom/themes/powerlevel10k

	# Install plugins
	ZSH_CUSTOM=~/.oh-my-zsh/custom/plugins
	git clone --quiet https://github.com/zsh-users/zsh-autosuggestions.git ${ZSH_CUSTOM}/zsh-autosuggestions
	git clone --quiet https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM}/zsh-syntax-highlighting
	git clone --quiet https://github.com/Pilaton/OhMyZsh-full-autoupdate.git ${ZSH_CUSTOM}/ohmyzsh-full-autoupdate
	git clone --quiet https://github.com/MichaelAquilina/zsh-you-should-use.git ${ZSH_CUSTOM}/you-should-use
	EOF
	
	log_success "Zsh plugins installed successfully"
}