project = "Chorus"
author = "Brian Koropoff"
copyright = "2025 Brian Koropoff"
version = "0.1.0"

templates_path = ['templates']

extensions = [
    "sphinx_lua_ls",
    "myst_parser"
]

html_theme = "sphinx_rtd_theme"

html_theme_options = {
    'collapse_navigation': False
}

html_logo = 'chorus.svg'

html_context = {
    'display_github': True,
    'github_user': 'bkoropoff',
    'github_repo': 'chorus',
}

lua_ls_project_root = "../lua"
lua_ls_backend = "emmylua"
lua_ls_apidoc_format = "md"
lua_ls_apidoc_separate_members = True

lua_ls_apidoc_roots = {
   "chorus": {
        "path": "api"
    }
}

lua_ls_default_options = {
    'members': "",
    'globals': "_",
    'recursive': "",
    'private-members': "_",
    'package-members': "_",
    'protected-members': "_",
    'inherited-members': "_",
    'module-member-order': "groupwise"
}
