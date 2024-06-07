local files = require("overseer.files")
local overseer = require("overseer")

local package_manager = "yarn"

---@type overseer.TemplateFileDefinition
local tmpl = {
  priority = 50,
  params = {
    args = { optional = true, type = "list", delimiter = " " },
    cwd = { optional = true },
    bin = { optional = true, type = "string" },
  },
  builder = function(params)
    return {
      cmd = { params.bin },
      args = params.args,
      cwd = params.cwd,
    }
  end,
}

---@param opts overseer.SearchParams
local function get_candidate_package_files(opts)
  -- Some projects have package.json files in subfolders, which are not the main project package.json file,
  -- but rather some submodule marker. This seems prevalent in react-native projects. See this for instance:
  -- https://stackoverflow.com/questions/51701191/react-native-has-something-to-use-local-folders-as-package-name-what-is-it-ca
  -- To cover that case, we search for package.json files starting from the current file folder, up to the
  -- working directory
  local matches = vim.fs.find("package.json", {
    upward = true,
    type = "file",
    path = opts.dir,
    stop = vim.fn.getcwd() .. "/..",
    limit = math.huge,
  })
  if #matches > 0 then
    return matches
  end
  -- we couldn't find any match up to the working directory.
  -- let's now search for any possible single match without
  -- limiting ourselves to the working directory.
  return vim.fs.find("package.json", {
    upward = true,
    type = "file",
    path = vim.fn.getcwd(),
  })
end

---@param opts overseer.SearchParams
---@return string|nil
local function get_package_file(opts)
  local candidate_packages = get_candidate_package_files(opts)
  -- go through candidate package files from closest to the file to least close
  for _, package in ipairs(candidate_packages) do
    local data = files.load_json_file(package)
    if data.scripts or data.workspaces then
      return package
    end
  end
  return nil
end

---@return boolean
local function check_for_workspaces()
  local package_file = get_package_file({ dir = vim.fn.getcwd() })

  if not package_file then
    return false
  end

  local data = files.load_json_file(package_file)

  return data.workspaces ~= nil
end

return {
  cache_key = function(opts)
    return get_package_file(opts)
  end,
  condition = {
    callback = function(opts)
      local package_file = get_package_file(opts)
      if not package_file then
        return false, "No package.json file found"
      end

      if not files.exists(files.join(vim.fn.getcwd(), "yarn.lock")) then
        return false, "Not a yarn project"
      end

      if not check_for_workspaces() then
        return false, "No workspaces found"
      end

      if vim.fn.executable(package_manager) == 0 then
        return false, string.format("Could not find command '%s'", package_manager)
      end

      return true
    end,
  },
  generator = function(opts, cb)
    local package = get_package_file(opts)

    if not package then
      cb({})
      return
    end

    local data = files.load_json_file(package)
    local ret = {}

    if data.scripts then
      for k in pairs(data.scripts) do
        table.insert(
          ret,
          overseer.wrap_template(
            tmpl,
            { name = string.format("%s[%s] %s", package_manager, data.name, k) },
            { args = { "run", k }, bin = package_manager, cwd = vim.fs.dirname(package) }
          )
        )
      end
    end

    cb(ret)
  end,
  check_for_workspaces = check_for_workspaces,
}
