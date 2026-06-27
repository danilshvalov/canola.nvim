local test_util = require('spec.test_util')
local util = require('oil.util')
local view = require('oil.view')

local function get_upvalue(fn, target)
  for i = 1, 20 do
    local name, value = debug.getupvalue(fn, i)
    if name == target then
      return value
    end
  end
end

local function demo_lines()
  local lines = {}
  for i = 1, 40 do
    lines[i] = string.format('/%d file_%02d', i, i)
  end
  return lines
end

describe('cursor constraints', function()
  after_each(function()
    test_util.reset_editor()
  end)

  it('does not error when a stale cursor row is beyond the loading buffer', function()
    local constrain_cursor = assert(get_upvalue(view.initialize, 'constrain_cursor'))
    local calc = assert(get_upvalue(constrain_cursor, 'calc_constrained_cursor_pos'))
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].buftype = 'nofile'
    vim.bo[bufnr].bufhidden = 'wipe'
    vim.bo[bufnr].swapfile = false
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, demo_lines())
    local stale = { 40, 0 }
    util.render_text(bufnr, { 'Loading', '[===]' }, { h_align = 'left', v_align = 'top' })
    assert.is_nil(calc(bufnr, nil, 'editable', stale))
  end)
end)

describe('cursor restoration', function()
  after_each(function()
    test_util.reset_editor()
  end)

  it('overrides BufWinEnter cursor restoration when opening parent', function()
    local oil = require('oil')
    local test_adapter = require('oil.adapters.test')
    require('oil.config').view_options.show_hidden = true

    test_adapter.test_set('/projects/foo/bar.txt', 'file')
    test_adapter.test_set('/docs/readme.md', 'file')

    -- Simulate a cursor-restoring plugin
    local au_id = vim.api.nvim_create_autocmd({ 'BufWinLeave', 'BufWinEnter' }, {
      pattern = '*',
      callback = function(args)
        local bufnr = vim.api.nvim_get_current_buf()
        if vim.bo[bufnr].filetype == 'oil' then
          if args.event == 'BufWinLeave' then
            vim.b[bufnr].oil_conflict_cursor = vim.api.nvim_win_get_cursor(0)
          else
            local remembered = vim.b[bufnr].oil_conflict_cursor
            if remembered then
              vim.api.nvim_win_set_cursor(0, remembered)
            end
          end
        end
      end,
    })

    test_util.actions.open({ 'oil-test:///' })
    test_util.actions.focus('docs/')
    assert.equals('docs', oil.get_cursor_entry().name)

    vim.cmd.edit({ args = { 'oil-test:///projects/' } })
    test_util.wait_oil_ready()
    assert.equals('oil-test:///projects/', vim.api.nvim_buf_get_name(0))

    oil.open()
    test_util.wait_oil_ready()
    -- The scheduled cursor enforcement runs after BufWinEnter autocmds
    assert.is_true(vim.wait(1000, function()
      local entry = oil.get_cursor_entry()
      return entry and entry.name == 'projects'
    end, 10))
    assert.equals('oil-test:///', vim.api.nvim_buf_get_name(0))
    assert.equals('projects', oil.get_cursor_entry().name)

    vim.api.nvim_del_autocmd(au_id)
  end)

  it('persists cursor position across sessions', function()
    local oil = require('oil')
    local test_adapter = require('oil.adapters.test')
    local view = require('oil.view')
    require('oil.config').view_options.show_hidden = true

    test_adapter.test_set('/projects/foo/bar.txt', 'file')
    test_adapter.test_set('/docs/readme.md', 'file')

    test_util.actions.open({ 'oil-test:///' })
    test_util.actions.focus('docs/')
    assert.equals('docs', oil.get_cursor_entry().name)

    view.save_persisted_cursor()

    -- Simulate a restart: reset_editor clears in-memory state but keeps the
    -- persisted file on disk. setup() reloads it automatically.
    test_util.reset_editor()
    test_adapter.test_set('/projects/foo/bar.txt', 'file')
    test_adapter.test_set('/docs/readme.md', 'file')

    test_util.actions.open({ 'oil-test:///' })
    test_util.wait_oil_ready()
    assert.equals('docs', oil.get_cursor_entry().name)
  end)
end)
