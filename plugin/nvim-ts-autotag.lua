---@class NvimTsAutotagTag
---@field start_tag string[]?
---@field start_name_tag string[]?
---@field end_tag string[]?
---@field end_name_tag string[]?
---@field element_tag string[]?
---@field skip_tag string[]?

local tbl_skip_tag =
    { "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr" }

---@type NvimTsAutotagTag
local HTML_TAG = {
    start_tag = { "start_tag", "STag" },
    start_name_tag = { "tag_name", "Name" },
    end_tag = { "end_tag", "ETag" },
    end_name_tag = { "tag_name", "Name" },
    element_tag = { "element" },
    skip_tag = { "quoted_attribute_value", "end_tag" },
}

---@type NvimTsAutotagTag
local JSX_TAG = {
    start_tag = { "jsx_opening_element", "start_tag" },
    start_name_tag = { "identifier", "nested_identifier", "tag_name", "member_expression", "jsx_identifier" },
    end_tag = { "jsx_closing_element", "end_tag" },
    end_name_tag = { "identifier", "tag_name" },
    element_tag = { "jsx_element", "element" },
    skip_tag = { "jsx_closing_element", "jsx_expression", "string", "jsx_attribute", "end_tag", "string_fragment" },
}

---@type NvimTsAutotagTag
local HBS_TAG = {
    start_tag = { "element_node_start" },
    start_name_tag = { "tag_name" },
    end_tag = { "element_node_end" },
    end_name_tag = { "tag_name" },
    element_tag = { "element_node" },
    skip_tag = { "element_node_end", "attribute_node", "concat_statement" },
}

---@type NvimTsAutotagTag
local RSTML_TAG = {
    start_tag = { "open_tag" },
    start_name_tag = { "node_identifier" },
    end_tag = { "close_tag" },
    end_name_tag = { "node_identifier" },
    element_tag = { "element_node" },
    skip_tag = { "close_tag", "node_attribute", "block" },
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
    typescriptreact = JSX_TAG,
    javascriptreact = JSX_TAG,
    tsx = JSX_TAG,
    glimmer = HBS_TAG,
    handlebars = HBS_TAG,
    hbs = HBS_TAG,
    svelte = HTML_TAG,
    rust = RSTML_TAG,
    javascript = {},
    typescript = {},
    eruby = {},
}

---@param parser vim.treesitter.LanguageTree
---@param range [integer, integer, integer, integer]
---@return string
local function get_lang(parser, range)
    for lang, child in pairs(parser:children()) do
        if lang ~= "comment" and child:contains(range) then
            return get_lang(child, range)
        end
    end
    return parser:lang()
end

---@param target TSNode?
---@param tag_pattern string[]
---@param skip_tag_pattern string[]?
---@return TSNode?
local function find_child_match(target, tag_pattern, skip_tag_pattern)
    if target == nil or vim.tbl_contains(tag_pattern, target:type()) then
        return target
    end
    for _, ptn in pairs(tag_pattern) do
        for node in target:iter_children() do
            local node_type = node:type()
            if node_type == ptn and not vim.tbl_contains(skip_tag_pattern or {}, node_type) then
                return node
            end
        end
    end
end

---@param target TSNode?
---@param tag_pattern string[]
---@param skip_tag_pattern string[]?
---@param max_depth integer
---@return TSNode?
local function find_parent_match(target, tag_pattern, skip_tag_pattern, max_depth)
    for _, ptn in pairs(tag_pattern) do
        local cur_node = target
        local cur_depth = 0
        while cur_node ~= nil do
            local node_type = cur_node:type()
            if vim.tbl_contains(skip_tag_pattern or {}, node_type) then
                return nil
            end
            if node_type == ptn then
                return cur_node
            end

            if cur_depth < max_depth then
                cur_depth = cur_depth + 1
                cur_node = cur_node:parent()
            else
                cur_node = nil
            end
        end
    end
    return nil
end

---@param bufnr integer
---@param ts_tag NvimTsAutotagTag
local function try_insert_close_tag(bufnr, ts_tag)
    local curr_node = vim.treesitter.get_node({ ignore_injections = false })
    local start_node = find_parent_match(curr_node, ts_tag.start_tag, ts_tag.skip_tag, 10)

    local start_tag = find_child_match(start_node, ts_tag.start_name_tag)
    if not start_tag then
        return
    end

    local start_tag_name = vim.treesitter.get_node_text(start_tag, bufnr)
    if vim.tbl_contains(tbl_skip_tag, start_tag_name) then
        return
    end

    local element_node = find_parent_match(start_tag, ts_tag.element_tag, nil, 2)
    local close_node = find_child_match(element_node, ts_tag.end_tag, ts_tag.end_name_tag)
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

            local ok, parser = pcall(vim.treesitter.get_parser)
            if not ok or not parser then
                return vim.api.nvim_win_set_cursor(0, { row, col + 1 })
            end
            parser:parse(true)

            local lang = get_lang(parser, { row - 1, col, row - 1, col })
            local ts_tag = filetype_to_type[lang] or filetype_to_type[vim.bo.filetype]
            if not ts_tag or vim.tbl_isempty(ts_tag) then
                return vim.api.nvim_win_set_cursor(0, { row, col + 1 })
            end

            try_insert_close_tag(args.buf, ts_tag)

            vim.api.nvim_win_set_cursor(0, { row, col + 1 })
        end, {
            buffer = 0,
        })
    end,
})
