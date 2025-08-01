# nvim-ts-autotag

Use treesitter to **autoclose** html tag

It works with:

- astro
- glimmer
- handlebars
- html
- javascript
- jsx
- markdown
- php
- rescript
- svelte
- tsx
- typescript
- vue
- xml

## Usage

```text
Before        Input         After
------------------------------------
<div           >              <div></div>
------------------------------------
```

## Setup

```lua
require("nvim-ts-autotag").setup()
```
