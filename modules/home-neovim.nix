{ pkgs, ... }:

{
  # Configure neovim via home-manager's programs.neovim module.
  programs.neovim = {
    enable = true;
    package = pkgs.neovim;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
    plugins = with pkgs.vimPlugins; [
      nvim-lspconfig
      nvim-treesitter.withAllGrammars
      plenary-nvim
      gruvbox-material
      mini-nvim
    ];

    extraPackages = with pkgs; [
      nodejs
      python3
      neovim
      python3Packages.pynvim
    ];
  };
}
