---@class NvimTsAutotagTag
---@field start_name_tag string[]
---@field end_tag string[]
---@field end_name_tag string[]
---@field element_tag string[]

local tbl_skip_tag =
    { "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr" }

---@type NvimTsAutotagTag
local HTML_TAG = {
    start_name_tag = { "tag_name", "Name" },
    end_tag = { "end_tag", "ETag" },
    end_name_tag = { "tag_name", "Name" },
    element_tag = { "element" },
}

---@type NvimTsAutotagTag
local JSX_TAG = {
    start_name_tag = { "identifier", "nested_identifier", "tag_name", "member_expression", "jsx_identifier" },
    end_tag = { "jsx_closing_element", "end_tag" },
    end_name_tag = { "identifier", "tag_name" },
    element_tag = { "jsx_element", "element" },
}

---@type NvimTsAutotagTag
local HBS_TAG = {
    start_name_tag = { "tag_name" },
    end_tag = { "element_node_end" },
    end_name_tag = { "tag_name" },
    element_tag = { "element_node" },
}

---@type NvimTsAutotagTag
local RSTML_TAG = {
    start_name_tag = { "node_identifier" },
    end_tag = { "close_tag" },
    end_name_tag = { "node_identifier" },
    element_tag = { "element_node" },
}

---@type table<string, NvimTsAutotagTag>
local filetype_to_type = {
    vue = HTML_TAG,
    astro = HTML_TAG,
    html = HTML_TAG,
    htmldjango = HTML_TAG,
    markdown = HTML_TAG,
    php = HTML_TAG,
    xml = HTML_TAG,
    svelte = HTML_TAG,
    eruby = HTML_TAG,
    typescriptreact = JSX_TAG,
    javascriptreact = JSX_TAG,
    tsx = JSX_TAG,
    rescript = JSX_TAG,
    javascript = JSX_TAG,
    typescript = JSX_TAG,
    glimmer = HBS_TAG,
    handlebars = HBS_TAG,
    hbs = HBS_TAG,
    rust = RSTML_TAG,
}

---@param target TSNode?
---@param tag_pattern string[]
---@return TSNode?
local function find_child_match(target, tag_pattern)
    if target == nil or vim.tbl_contains(tag_pattern, target:type()) then
        return target
    end
    return vim.iter(target:iter_children()):find(function(it)
        return vim.tbl_contains(tag_pattern, it:type())
    end)
end

---@param target TSNode?
---@param tag_pattern string[]
---@param max_depth integer
---@return TSNode?
local function find_parent_match(target, tag_pattern, max_depth)
    local cur_node = target
    local cur_depth = 0
    while cur_node ~= nil and cur_depth <= max_depth do
        if vim.tbl_contains(tag_pattern, cur_node:type()) then
            return cur_node
        end
        cur_node = cur_node:parent()
        cur_depth = cur_depth + 1
    end
    return nil
end

---@param bufnr integer
---@param ts_tag NvimTsAutotagTag
local function try_insert_close_tag(bufnr, ts_tag)
    local curr_node = vim.treesitter.get_node({ ignore_injections = false })
    local start_tag = find_child_match(curr_node, ts_tag.start_name_tag)
    if not start_tag then
        return
    end

    local start_tag_name = vim.treesitter.get_node_text(start_tag, bufnr)
    if vim.tbl_contains(tbl_skip_tag, start_tag_name) then
        return
    end

    local element_node = find_parent_match(start_tag, ts_tag.element_tag, 2)
    local close_node = find_child_match(element_node, ts_tag.end_tag)
    local close_tag = find_child_match(close_node, ts_tag.end_name_tag)

    -- If we have a closing tag that is the same as the start tag, we should not autofill it
    if close_tag ~= nil then
        local close_tag_name = vim.treesitter.get_node_text(close_tag, bufnr)
        if start_tag:range() == close_tag:range() and start_tag_name == close_tag_name then
            return
        end
    end

    vim.api.nvim_put({ string.format("</%s>", start_tag_name) }, "", true, false)
end

vim.api.nvim_create_autocmd("FileType", {
    pattern = vim.tbl_keys(filetype_to_type),
    callback = function(args)
        vim.keymap.set("i", ">", function()
            local row, col = unpack(vim.api.nvim_win_get_cursor(0))
            vim.api.nvim_buf_set_text(args.buf, row - 1, col, row - 1, col, { ">" })

            -- Self closing tags should not be closed
            if vim.api.nvim_get_current_line():sub(col, col) == "/" then
                return vim.api.nvim_win_set_cursor(0, { row, col + 1 })
            end

            local ok, parser = pcall(vim.treesitter.get_parser)
            if not ok or not parser then
                return vim.api.nvim_win_set_cursor(0, { row, col + 1 })
            end
            parser:parse(true)

            local ts_tag = filetype_to_type[vim.bo.filetype]
            try_insert_close_tag(args.buf, ts_tag)

            vim.api.nvim_win_set_cursor(0, { row, col + 1 })
        end, {
            buffer = 0,
        })
    end,
})
