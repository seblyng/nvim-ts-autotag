local M = {}

---@class NvimTsAutotagTag
---@field start_tag_pattern string[]?
---@field start_name_tag_pattern string[]?
---@field end_tag_pattern string[]?
---@field end_name_tag_pattern string[]?
---@field element_tag string[]?
---@field skip_tag_pattern string[]?

local tbl_skip_tag =
    { "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr" }

---@type NvimTsAutotagTag
local HTML_TAG = {
    start_tag_pattern = { "start_tag" },
    start_name_tag_pattern = { "tag_name" },
    end_tag_pattern = { "end_tag" },
    end_name_tag_pattern = { "tag_name" },
    element_tag = { "element" },
    skip_tag_pattern = { "quoted_attribute_value", "end_tag" },
}

---@type NvimTsAutotagTag
local JSX_TAG = {
    start_tag_pattern = { "jsx_opening_element", "start_tag" },
    start_name_tag_pattern = { "identifier", "nested_identifier", "tag_name", "member_expression", "jsx_identifier" },
    end_tag_pattern = { "jsx_closing_element", "end_tag" },
    end_name_tag_pattern = { "identifier", "tag_name" },
    element_tag = { "jsx_element", "element" },
    skip_tag_pattern = {
        "jsx_closing_element",
        "jsx_expression",
        "string",
        "jsx_attribute",
        "end_tag",
        "string_fragment",
    },
}

---@type NvimTsAutotagTag
local HBS_TAG = {
    start_tag_pattern = { "element_node_start" },
    start_name_tag_pattern = { "tag_name" },
    end_tag_pattern = { "element_node_end" },
    end_name_tag_pattern = { "tag_name" },
    element_tag = { "element_node" },
    skip_tag_pattern = { "element_node_end", "attribute_node", "concat_statement" },
}

---@type NvimTsAutotagTag
local SVELTE_TAG = {
    start_tag_pattern = { "start_tag" },
    start_name_tag_pattern = { "tag_name" },
    end_tag_pattern = { "end_tag" },
    end_name_tag_pattern = { "tag_name" },
    element_tag = { "element" },
    skip_tag_pattern = { "quoted_attribute_value", "end_tag" },
}

---@type NvimTsAutotagTag
local RSTML_TAG = {
    start_tag_pattern = { "open_tag" },
    start_name_tag_pattern = { "node_identifier" },
    end_tag_pattern = { "close_tag" },
    end_name_tag_pattern = { "node_identifier" },
    element_tag = { "element_node" },
    skip_tag_pattern = { "close_tag", "node_attribute", "block" },
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
    svelte = SVELTE_TAG,
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

---@param parser vim.treesitter.LanguageTree
---@return NvimTsAutotagTag|nil
local function get_ts_tag(parser)
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local range = { row - 1, col, row - 1, col }
    local lang = get_lang(parser, range)
    local ts_tag = filetype_to_type[lang] or filetype_to_type[vim.bo.filetype]
    return not vim.tbl_isempty(ts_tag) and ts_tag or nil
end

---@param target TSNode?
---@param tag_pattern string[]
---@param skip_tag_pattern string[]?
---@return TSNode?
local function find_child_match(target, tag_pattern, skip_tag_pattern)
    if target == nil then
        return nil
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
---@param max_depth integer?
---@return TSNode?
local function find_parent_match(target, tag_pattern, skip_tag_pattern, max_depth)
    max_depth = max_depth or 10
    if target == nil then
        return nil
    end
    for _, ptn in pairs(tag_pattern) do
        local cur_node = target --[[@as TSNode?]]
        local cur_depth = 0
        while cur_node ~= nil do
            local node_type = cur_node:type()
            if vim.tbl_contains(skip_tag_pattern or {}, node_type) then
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

---@param node TSNode?
---@return string?
local function get_tag_name(node)
    if node == nil then
        return nil
    end

    local txt = vim.treesitter.get_node_text(node, vim.api.nvim_get_current_buf())
    local tag_name = vim.split(txt, "\n")[1]

    if tag_name and #tag_name > 3 then
        tag_name = tag_name:gsub("</", ""):gsub(">", ""):gsub("<", "")
    end
    return tag_name
end

---@param target TSNode?
---@param name_tag_pattern string[]
---@return TSNode?
local function find_tag_node(target, name_tag_pattern)
    if not target then
        return nil
    end

    local name_node = find_child_match(target, name_tag_pattern)
    if name_node then
        return name_node
    end

    -- check current node is have same name of tag_match
    return vim.tbl_contains(name_tag_pattern, target:type()) and target or nil
end

---@param parser vim.treesitter.LanguageTree
---@return string?
local function check_close_tag(parser)
    local ts_tag = get_ts_tag(parser)
    if ts_tag == nil then
        return nil
    end

    local curr_node = vim.treesitter.get_node({ ignore_injections = false })
    local start_node = find_parent_match(curr_node, ts_tag.start_tag_pattern, ts_tag.skip_tag_pattern)

    local start_tag_node = find_tag_node(start_node, ts_tag.start_name_tag_pattern)
    local start_tag_name = get_tag_name(start_tag_node)

    if not start_tag_node or not start_tag_name or vim.tbl_contains(tbl_skip_tag, start_tag_name) then
        return nil
    end

    local element_node = find_parent_match(start_tag_node, ts_tag.element_tag, nil, 2)
    local close_node = find_child_match(element_node, ts_tag.end_tag_pattern, ts_tag.end_name_tag_pattern)
    local close_tag_node = find_tag_node(close_node, ts_tag.end_name_tag_pattern)

    -- We don't have a close node, so autofill it
    if close_tag_node == nil then
        return start_tag_name
    end

    -- We already have the same closing tag, so ignore
    if start_tag_node:range() == close_tag_node:range() and start_tag_name == get_tag_name(close_tag_node) then
        return nil
    end

    return start_tag_name
end

function M.setup()
    vim.api.nvim_create_autocmd("FileType", {
        pattern = vim.tbl_keys(filetype_to_type),
        callback = function()
            vim.keymap.set("i", ">", function()
                local row, col = unpack(vim.api.nvim_win_get_cursor(0))
                vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, { ">" })

                local ok, parser = pcall(vim.treesitter.get_parser)
                if not ok or not parser then
                    return
                end
                parser:parse(true)
                local tag_name = check_close_tag(parser)
                if tag_name ~= nil then
                    vim.api.nvim_put({ string.format("</%s>", tag_name) }, "", true, false)
                end

                vim.api.nvim_win_set_cursor(0, { row, col + 1 })
            end, {
                buffer = 0,
            })
        end,
    })
end

return M
