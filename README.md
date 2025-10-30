# nvim-bacon

This plugin enables viewing the locations found in a `.bacon-locations` file, and jumping to them.

## Installation in Neovim

This extension may be imported with a standard plugin system.

### [vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'Canop/nvim-bacon'
```

### [lazyvim](https://www.lazyvim.org/):

In eg `lua/config/plugins/bacon.lua`:

```vim
return {
    -- other plugins
    {
        "Canop/nvim-bacon",
        config = function()
            require("bacon").setup({
                quickfix = {
                    enabled = true, -- Enable Quickfix integration
                    event_trigger = true, -- Trigger QuickFixCmdPost after populating Quickfix list
                },
            })
        end,
    },
}
```

## Bacon configuration

You must [enable locations export in bacon](https://dystroy.org/bacon/config/#exports).

Change/uncomment the exports part of your prefs.toml file:

```toml
[exports.locations]
auto = true
path = ".bacon-locations"
line_format = "{kind} {path}:{line}:{column} {message}"
```

## Usage

You'll use this plugin in nvim while a bacon instance is running in another panel, probably side to it.

To navigate among errors and warnings, you'll use either the standard Quickfix feature of your editor or nvim-bacon dedicated commands and view.

### Specialized Commands and View

The following functions are exposed by the plugin:

| Function         | Usage                                                      |
| ---------------- | ---------------------------------------------------------- |
| `:BaconLoad`     | Silently load the locations of the `.bacon-locations` file |
| `:BaconShow`     | Display the locations in a floating window                 |
| `:BaconList`     | Does `:BaconLoad` then `:BaconShow`                        |
| `:BaconPrevious` | Jump to the previous location in the current list          |
| `:BaconNext`     | Jump to the next location in the current list              |
| `:BaconSend`     | Send a command to bacon via its socket (requires `listen = true` in bacon config) |

You should define at least two shortcuts, for example like this:

```vimscript
nnoremap ! :BaconLoad<CR>:w<CR>:BaconNext<CR>
nnoremap , :BaconList<CR>
```

or, if using lazyVim, in lua/config/keymaps.lua:

```vim
local map = LazyVim.safe_keymap_set
map("n", "!", ":BaconLoad<CR>:w<CR>:BaconNext<CR>", { desc = "Navigate to next bacon location" })
map("n", ",", ":BaconList<CR>", { desc = "Open bacon locations list" })
```

The first shortcut navigates from location to location, without opening the window.
This is probably the one you'll use all the time.
You may notice it loads the list (`:BaconLoad`) then saves the current document (`:w`), to prevent both race conditions and having a bunch of unsaved buffers.

The second shortcut, which is mapped to the <kbd>,</kbd> key, opens the list of all bacon locations:

![list-and-bacon](doc/list-and-bacon.png)

When the list is open, you can select a line and hit <kbd>enter</kbd> or just hit the number of the location if it's in 1-9.
As there's no need to wait for the window to appear, you may just type <kbd>,</kbd><kbd>3</kbd> to go to location 3 without opening the window.

You may define other shortcuts using the various API functions.

### Quickfix Integration

Errors and warnings also populate the [Quicklist](http://neovim.io/doc/user/quickfix.html) list by default.

You can disable this feature with this configuration:

```lua
require("bacon").setup({
    quickfix  = {
         enabled = false, -- true to populate the quickfix list with bacon errors and warnings
         event_trigger = true, -- triggers the QuickFixCmdPost event after populating the quickfix list
    }
)}
```

### Sending Commands to Bacon

If you enable socket listening in your bacon configuration (by setting `listen = true` in your prefs.toml), you can send commands to bacon from nvim using `:BaconSend`.

First, configure bacon to listen on a socket by adding this to your `prefs.toml`:

```toml
listen = true
```

Then you can send any bacon action to the running instance:

```vim
:BaconSend job:test        " Switch to the 'test' job
:BaconSend job:clippy      " Switch to the 'clippy' job
:BaconSend scroll-lines(-2) " Scroll bacon display up by 2 lines
```

This is particularly useful for creating keybindings to trigger different bacon jobs:

```vimscript
nnoremap <leader>bt :BaconSend job:test<CR>
nnoremap <leader>bc :BaconSend job:clippy<CR>
nnoremap <leader>br :BaconSend job:run<CR>
```

Or in LazyVim's `lua/config/keymaps.lua`:

```lua
local map = LazyVim.safe_keymap_set
map("n", "<leader>bt", ":BaconSend job:test<CR>", { desc = "Bacon: run tests" })
map("n", "<leader>bc", ":BaconSend job:clippy<CR>", { desc = "Bacon: run clippy" })
map("n", "<leader>br", ":BaconSend job:run<CR>", { desc = "Bacon: run" })
```

See the [bacon documentation](https://dystroy.org/bacon/config/#listen) for more information about available actions.
