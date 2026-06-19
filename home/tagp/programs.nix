{ pkgs, inputs, ... }: {
  programs.git = {
    enable = true;
		settings = {
			user.name = "thomas";
			user.email = "thomas@petersson.priv.no";
		};
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    withRuby = false;
    withPython3 = false;
  };

	xdg.configFile."nvim" = {
		source = inputs.nvim-config;
		recursive = true;
	};

  home.packages = with pkgs; [
    # user-specific packages that don't need to be system-wide
    ripgrep
    fd
		tmux
		nixd
		gcc
		tree-sitter
		lua-language-server
		vscode-langservers-extracted
		bash-language-server
		marksman
		fzf
  ];

	programs.zoxide.enable = true;

	programs.bash = {
    enable = true;
    shellAliases = {
      mysql = "mariadb";
      cd = "z";
    };
    initExtra = ''
      export NIX_SHELL_DEPTH=$(( ''${NIX_SHELL_DEPTH:-0} + 1 ))

      _nix_shell_indicator() {
        local label=""
        local nix_paths=$(echo "$PATH" | tr ':' '\n' | grep -c '/nix/store')

        if [[ -n "$IN_NIX_SHELL" ]]; then
          label="''${name:-''${IN_NIX_SHELL}}"
        elif [[ $nix_paths -ge 1 ]]; then
          label="nix-shell"
        else
          return
        fi

        echo -n "(''${label}:''${NIX_SHELL_DEPTH})"
      }

      PS1='\[\e[0;36m\]$(_nix_shell_indicator)\[\e[0m\] \u@\h:\w\$ '
    '';
  };
}
