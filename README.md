# ~/. 📂 My dotfiles
managed with [`chezmoi`](https://github.com/twpayne/chezmoi).

## Instalation
Install (new machine) with:

```console
$ sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply ybarsotti
```


## Common Chezmoi Commands

A quick reference for the most frequently used `chezmoi` commands for day-to-day operations.

### Core Workflow

This is the most common cycle for making changes to your dotfiles.

- **`chezmoi edit [target-file]`**
  - **Purpose**: The safest way to edit a managed dotfile. It opens the *source file* in your editor, not the destination file in your home directory.
  - **Example**: `chezmoi edit ~/.zshrc`

- **`chezmoi diff`**
  - **Purpose**: Shows a diff of the changes that would be made by `chezmoi apply`. It's highly recommended to run this before applying to see what will change.
  - **Example**: `chezmoi diff`

- **`chezmoi apply`**
  - **Purpose**: Applies the changes from your source directory to your home directory, making it match the desired state. This is the main command to sync your dotfiles. Use the `-v` (verbose) flag to see what it's doing.
  - **Example**: `chezmoi apply -v`

### Managing Files

Commands for adding, removing, or changing which files are managed by `chezmoi`.

- **`chezmoi add [target-file]`**
  - **Purpose**: Adds a new file from your home directory to `chezmoi`'s source state.
  - **Example**: `chezmoi add ~/.config/alacritty/alacritty.yml`

- **`chezmoi forget [target-file]`**
  - **Purpose**: Removes a file from `chezmoi`'s management. The file is removed from the source directory but is **left untouched** in your home directory.
  - **Example**: `chezmoi forget ~/.bashrc`

- **`chezmoi remove [target-file]`**
  - **Purpose**: The more destructive version of `forget`. It removes the file from the source directory **and also deletes it** from your home directory.
  - **Example**: `chezmoi remove ~/.old_config_file`

### Syncing & Status

Commands for keeping multiple machines in sync and checking the current state.

- **`chezmoi update`**
  - **Purpose**: Pulls the latest changes from your dotfiles git repository and then runs `chezmoi apply`. This is the primary command for syncing changes *to* a machine.
  - **Example**: `chezmoi update`

- **`chezmoi status`**
  - **Purpose**: Shows a summary of files that have been modified in your home directory and differ from what's in the source directory.
  - **Example**: `chezmoi status`

- **`chezmoi cd`**
  - **Purpose**: A handy shortcut to open a new shell session directly in the source directory (`~/.local/share/chezmoi`).
  - **Example**: `chezmoi cd`

### Destructive Operations

> **Warning**: Use the following commands with caution as they can delete files.

- **`chezmoi purge`**
  - **Purpose**: Removes everything managed by `chezmoi` from your home directory. This effectively uninstalls your managed dotfiles, leaving your system clean.
  - **Example**: `chezmoi purge`
