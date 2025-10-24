{ pkgs, ... }:

{
  # Configure neovim via home-manager's programs.neovim module.
  programs.neovim = {
    enable = true;
    package = pkgs.neovim;

    # Minimal init.vim content using embedded lua block; expand as needed.
    extraConfig = ''
lua << EOF
require('packer').startup(function(use)
  use 'wbthomason/packer.nvim'
  use 'neovim/nvim-lspconfig'
  use 'nvim-treesitter/nvim-treesitter'
  use 'hrsh7th/nvim-cmp'
  use 'hrsh7th/cmp-nvim-lsp'
end)
EOF
'';

    # Provide some extra runtime packages commonly useful for development
    extraPackages = with pkgs; [ nodejs python3 neovim python3Packages.pynvim ];
  };
}
