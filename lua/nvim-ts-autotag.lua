local group = vim.api.nvim_create_augroup("nvim-ts-autotag", { clear = true })

local M = {}

-- stylua: ignore
local tbl_filetypes = {
    'html', 'javascript', 'typescript', 'javascriptreact', 'typescriptreact', 'svelte', 'vue', 'tsx', 'jsx',
    'xml',
    'php',
    'markdown',
    'astro', 'glimmer', 'handlebars', 'hbs',
    'htmldjango',
    'eruby'
}

-- stylua: ignore
local tbl_skip_tag = {
    'area', 'base', 'br', 'col', 'command', 'embed', 'hr', 'img', 'slot',
    'input', 'keygen', 'link', 'meta', 'param', 'source', 'track', 'wbr', 'menuitem'
}

-- stylua: ignore
local HTML_TAG = {
    filetypes = {
        'astro',
        'html',
        'htmldjango',
        'markdown',
        'php',
        'xml',
    },
    start_tag_pattern      = { 'start_tag' },
    start_name_tag_pattern = { 'tag_name' },
    end_tag_pattern        = { 'end_tag' },
    end_name_tag_pattern   = { 'tag_name' },
    close_tag_pattern      = { 'erroneous_end_tag' },
    close_name_tag_pattern = { 'erroneous_end_tag_name' },
    element_tag            = { 'element' },
    skip_tag_pattern       = { 'quoted_attribute_value', 'end_tag' },
}
-- stylua: ignore
local JSX_TAG = {
    filetypes              = {
        'typescriptreact', 'javascriptreact', 'javascript.jsx',
        'typescript.tsx', 'javascript', 'typescript', 'rescript'
    },
    start_tag_pattern      = { 'jsx_opening_element', 'start_tag' },
    start_name_tag_pattern = { 'identifier', 'nested_identifier', 'tag_name', 'member_expression', 'jsx_identifier' },
    end_tag_pattern        = { 'jsx_closing_element', 'end_tag' },
    end_name_tag_pattern   = { 'identifier', 'tag_name' },
    close_tag_pattern      = { 'jsx_closing_element', 'nested_identifier' },
    close_name_tag_pattern = { 'member_expression', 'nested_identifier', 'jsx_identifier', 'identifier', '>' },
    element_tag            = { 'jsx_element', 'element' },
    skip_tag_pattern       = {
        'jsx_closing_element', 'jsx_expression', 'string', 'jsx_attribute', 'end_tag',
        'string_fragment'
    },

}


-- stylua: ignore
local HBS_TAG = {
    filetypes              = { 'glimmer', 'handlebars', 'hbs', 'htmldjango' },
    start_tag_pattern      = { 'element_node_start' },
    start_name_tag_pattern = { 'tag_name' },
    end_tag_pattern        = { 'element_node_end' },
    end_name_tag_pattern   = { 'tag_name' },
    close_tag_pattern      = { 'element_node_end' },
    close_name_tag_pattern = { 'tag_name' },
    element_tag            = { 'element_node' },
    skip_tag_pattern       = { 'element_node_end', 'attribute_node', 'concat_statement' },
}


-- stylua: ignore
local SVELTE_TAG = {
    filetypes              = { 'svelte' },
    start_tag_pattern      = { 'start_tag' },
    start_name_tag_pattern = { 'tag_name' },
    end_tag_pattern        = { 'end_tag' },
    end_name_tag_pattern   = { 'tag_name' },
    close_tag_pattern      = { 'ERROR' },
    close_name_tag_pattern = { 'ERROR', 'erroneous_end_tag_name' },
    element_tag            = { 'element' },
    skip_tag_pattern       = { 'quoted_attribute_value', 'end_tag' },
}

local all_tag = {
    HBS_TAG,
    SVELTE_TAG,
    JSX_TAG,
}

local get_node_text = function(node)
    local txt = vim.treesitter.get_node_text(node, vim.api.nvim_get_current_buf())
    return vim.split(txt, "\n") or {}
end

local verify_node = function(node, node_tag)
    local txt = vim.treesitter.get_node_text(node, vim.api.nvim_get_current_buf())
    return txt:match(string.format("^<%s>", node_tag)) and txt:match(string.format("</%s>$", node_tag))
end

local function is_in_table(tbl, val)
    local item = vim.iter(tbl or {}):find(function(value)
        return val == value
    end)
    return item ~= nil
end

local buffer_tag = {}

local setup_ts_tag = function()
    local bufnr = vim.api.nvim_get_current_buf()
    for _, value in pairs(all_tag) do
        if is_in_table(value.filetypes, vim.bo.filetype) then
            buffer_tag[bufnr] = value
            return value
        end
    end
    buffer_tag[bufnr] = HTML_TAG
end

-- TODO: Does not work yet here nor on master. It looks like it stops when
-- injected range is over
local function is_in_template_tag()
    local cursor_node = vim.treesitter.get_node({ ignore_injections = false })
    if not cursor_node then
        return false
    end

    local has_element = false
    local has_template_string = false

    local current_node = cursor_node
    while not (has_element and has_template_string) and current_node do
        if not has_element and current_node:type() == "element" then
            has_element = true
        end
        if not has_template_string and current_node:type() == "template_string" then
            has_template_string = true
        end
        current_node = current_node:parent()
    end

    return has_element and has_template_string
end

local function get_ts_tag()
    if is_in_template_tag() then
        return HTML_TAG
    else
        return buffer_tag[vim.api.nvim_get_current_buf()]
    end
end

local function find_child_match(opts)
    if opts.target == nil then
        return nil
    end
    for _, ptn in pairs(opts.tag_pattern) do
        for node in opts.target:iter_children() do
            local node_type = node:type()
            if node_type == ptn and not is_in_table(opts.skip_tag_pattern, node_type) then
                return node
            end
        end
    end
end

local function find_parent_match(opts)
    local max_depth = opts.max_depth or 10
    if opts.target == nil then
        return nil
    end
    for _, ptn in pairs(opts.tag_pattern) do
        local cur_node = opts.target
        local cur_depth = 0
        while cur_node ~= nil do
            local node_type = cur_node:type()
            if is_in_table(opts.skip_tag_pattern, node_type) then
                return nil
            end
            if node_type ~= nil and node_type == ptn then
                return cur_node
            elseif cur_depth < max_depth then
                cur_depth = cur_depth + 1
                cur_node = cur_node:parent()
            else
                cur_node = nil
            end
        end
    end
    return nil
end

local function get_tag_name(node)
    local tag_name = nil
    if node ~= nil then
        tag_name = get_node_text(node)[1]
        if tag_name and #tag_name > 3 then
            tag_name = tag_name:gsub("</", ""):gsub(">", ""):gsub("<", "")
        end
    end
    return tag_name
end

local function find_tag_node(opts)
    if not opts.target then
        opts.target = find_parent_match({
            target = opts.tag_node,
            tag_pattern = opts.element_tag,
            max_depth = 2,
        })
    end

    local node = opts.find_child and find_child_match(opts) or find_parent_match(opts)
    if node == nil then
        return nil
    end

    local name_node = find_child_match({ target = node, tag_pattern = opts.name_tag_pattern })
    if name_node then
        return name_node
    end

    -- check current node is have same name of tag_match
    return is_in_table(opts.name_tag_pattern, node:type()) and node or nil
end

local function check_close_tag()
    local ts_tag = get_ts_tag()
    local tag_node = find_tag_node({
        target = vim.treesitter.get_node({ ignore_injections = false }),
        tag_pattern = ts_tag.start_tag_pattern,
        name_tag_pattern = ts_tag.start_name_tag_pattern,
        skip_tag_pattern = ts_tag.skip_tag_pattern,
    })
    -- case 6,9 check close on exist node
    local close_tag_node = find_tag_node({
        find_child = true,
        tag_node = tag_node,
        element_tag = ts_tag.element_tag,
        tag_pattern = ts_tag.end_tag_pattern,
        name_tag_pattern = ts_tag.end_name_tag_pattern,
    })

    local tag_name = get_tag_name(tag_node)
    if tag_node == nil or tag_name == nil or is_in_table(tbl_skip_tag, tag_name) then
        return nil
    end

    -- If we already have a close tag
    if
        close_tag_node ~= nil
        and tag_node:range() == close_tag_node:range()
        and tag_name == get_tag_name(close_tag_node)
    then
        return nil
    end

    return tag_name
end

local function replace_text_node(node, tag_name)
    if node == nil then
        return
    end
    local start_row, start_col, end_row, end_col = node:range()
    if start_row == end_row then
        local line = vim.fn.getline(start_row + 1)
        local newline = line:sub(0, start_col) .. tag_name .. line:sub(end_col + 1, string.len(line))
        vim.api.nvim_buf_set_lines(0, start_row, start_row + 1, true, { newline })
    end
end

local function validate_tag_regex(node, start_regex, end_regex)
    if node == nil then
        return false
    end
    local texts = get_node_text(node)
    return string.match(texts[1], start_regex) and string.match(texts[#texts], end_regex)
end

local function validate_start_tag(node)
    return validate_tag_regex(node, "^%<%w", "%>$")
end

local function validate_close_tag(node)
    return validate_tag_regex(node, "^%<%/%w", "%>$")
end

local function rename_start_tag()
    local ts_tag = get_ts_tag()
    local tag_node = find_tag_node({
        target = vim.treesitter.get_node({ ignore_injections = false }),
        tag_pattern = ts_tag.start_tag_pattern,
        name_tag_pattern = ts_tag.start_name_tag_pattern,
        skip_tag_pattern = ts_tag.skip_tag_pattern,
    })

    if tag_node == nil or not validate_start_tag(tag_node:parent()) then
        return
    end

    local close_tag_node = find_tag_node({
        find_child = true,
        tag_node = tag_node,
        element_tag = ts_tag.element_tag,
        tag_pattern = ts_tag.close_tag_pattern,
        name_tag_pattern = ts_tag.close_name_tag_pattern,
    })

    local close_tag_name = get_tag_name(close_tag_node)
    local tag_name = get_tag_name(tag_node)
    if close_tag_name and tag_name ~= close_tag_name then
        if close_tag_name == ">" then
            tag_name = tag_name .. ">"
        end
        replace_text_node(close_tag_node, tag_name)
    end
end

local function rename_end_tag()
    local ts_tag = get_ts_tag()
    local tag_node = find_tag_node({
        target = vim.treesitter.get_node({ ignore_injections = false }),
        tag_pattern = ts_tag.close_tag_pattern,
        name_tag_pattern = ts_tag.close_name_tag_pattern,
    })

    -- we check if that node text match </>
    if tag_node == nil or not (validate_close_tag(tag_node:parent()) or validate_close_tag(tag_node)) then
        return
    end

    local start_tag_node = find_tag_node({
        find_child = true,
        element_tag = ts_tag.element_tag,
        tag_node = tag_node,
        tag_pattern = ts_tag.start_tag_pattern,
        name_tag_pattern = ts_tag.start_name_tag_pattern,
    })

    if start_tag_node == nil or not validate_start_tag(start_tag_node:parent()) then
        return
    end

    local tag_name = get_tag_name(tag_node)
    if tag_name ~= get_tag_name(start_tag_node) then
        replace_text_node(start_tag_node, tag_name)
    end
end

local function validate_rename()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()
    local char = line:sub(cursor[2] + 1, cursor[2] + 1)
    local prev_char = line:sub(cursor[2], cursor[2])
    -- only rename when last character is a word or end of tag
    return string.match(char, "%w") or string.match(prev_char, "%w")
end

local rename_tag = function()
    if not validate_rename() then
        return
    end
    local ok, parser = pcall(vim.treesitter.get_parser)
    if not ok then
        return
    end
    parser:parse(true)
    rename_start_tag()
    rename_end_tag()
end

local attach = function()
    if is_in_table(tbl_filetypes, vim.bo.filetype) then
        setup_ts_tag()

        vim.keymap.set("i", ">", function()
            local row, col = unpack(vim.api.nvim_win_get_cursor(0))
            vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, { ">" })

            local ok, parser = pcall(vim.treesitter.get_parser)
            if not ok then
                return
            end
            parser:parse(true)
            local tag_name = check_close_tag()
            if tag_name ~= nil then
                vim.api.nvim_put({ string.format("</%s>", tag_name) }, "", true, false)
                vim.cmd([[normal! F>]])
            end

            vim.api.nvim_win_set_cursor(0, { row, col + 1 })
        end, {
            buffer = 0,
        })

        vim.api.nvim_create_autocmd({ "InsertLeave" }, {
            group = group,
            buffer = 0,
            callback = rename_tag,
        })
    end
end

function M.setup(opts)
    opts = opts or {}

    vim.api.nvim_create_autocmd("FileType", {
        pattern = "*",
        callback = function()
            attach()
        end,
    })
    vim.api.nvim_create_autocmd("BufDelete", {
        pattern = "*",
        callback = function()
            buffer_tag[vim.api.nvim_get_current_buf()] = nil
        end,
    })
end

return M
