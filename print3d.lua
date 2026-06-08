local component = require("component")
local shell = require("shell")

local addresses = {}
for address in component.list("printer3d") do
  table.insert(addresses, address)
  print(#addresses .. ": " .. address)
end
if #addresses > 1 then
  io.write("Choose printer: ")
  local index
  repeat
    index = tonumber(io.read("*n"))
    if not (index and addresses[index]) then
      io.write("\nInvalid index!\nChoose printer: ")
    end
  until index and addresses[index]
  component.setPrimary("printer3d", addresses[index])
end

local printer = component.printer3d

local args = shell.parse(...)
if #args < 1 then
  io.write("Usage: print3d FILE [count]\n")
  os.exit(0)
end
local count = 1
if #args > 1 then
  count = assert(tonumber(args[2]), tostring(args[2]) .. " is not a valid count")
end

local file, reason = io.open(args[1], "r")
if not file then
  io.stderr:write("Failed opening file: " .. reason .. "\n")
  os.exit(1)
end

local rawdata = file:read("*all")
file:close()
local data, reason = load("return " .. rawdata)
if not data then
  io.stderr:write("Failed loading model: " .. reason .. "\n")
  os.exit(2)
end
data = data()

-- Вспомогательная функция для настройки и запуска печати ОДНОГО блока
local function printBlock(blockData)
  io.write("Configuring block: '" .. (blockData.label or "unnamed") .. "'...\n")
  printer.reset()
  if blockData.label then
    printer.setLabel(blockData.label)
  end
  if blockData.tooltip then
    printer.setTooltip(blockData.tooltip)
  end
  if blockData.lightLevel and printer.setLightLevel then
    printer.setLightLevel(blockData.lightLevel)
  end
  if blockData.emitRedstone then
    printer.setRedstoneEmitter(blockData.emitRedstone)
  end
  if blockData.buttonMode then
    printer.setButtonMode(blockData.buttonMode)
  end
  if blockData.collidable and printer.setCollidable then
    printer.setCollidable(not not blockData.collidable[1], not not blockData.collidable[2])
  end
  
  for i, shape in ipairs(blockData.shapes or {}) do
    -- pcall защищает от прерывания скрипта при невалидных фигурах
    local ok, result, reason = pcall(printer.addShape, shape[1], shape[2], shape[3], shape[4], shape[5], shape[6], shape.texture, shape.state, shape.tint)
    if not ok then
      io.write("Failed adding shape (error): " .. tostring(result) .. "\n")
    elseif not result then
      io.write("Failed adding shape: " .. tostring(reason) .. "\n")
    end
  end

  -- Защита от печати пустых блоков
  local inactive = printer.getShapeCount()
  if inactive == 0 then
    io.write("Block contains 0 shapes. Skipping empty block (air).\n")
    return true
  end

  io.write("Shapes loaded: " .. inactive .. " inactive, " .. select(2, printer.getShapeCount()) .. " active\n")
  
  -- pcall защищает от прерывания программы при ошибках отправки в очередь
  local ok, result, reason = pcall(printer.commit, count)
  if not ok then
    io.stderr:write("Failed committing job (error): " .. tostring(result) .. "\n")
    return false
  elseif result then
    io.write("Job successfully committed! Please wait...\n")
    return true
  else
    io.stderr:write("Failed committing job: " .. tostring(reason) .. "\n")
    return false
  end
end

-- Вспомогательная функция ожидания завершения работы принтера
local function waitForPrinter()
  io.write("Printing in progress... Please extract finished block when ready.")
  while true do
    local status, progress = printer.status()
    if status == "idle" then
      io.write("\nBlock finished!\n")
      break
    end
    os.sleep(1)
    io.write(".")
    io.flush()
  end
end

-- Главная логика печати
if data.multiblock then
  io.write("Detected combined multi-block model (" .. #data.blocks .. " blocks total)\n")
  for i, block in ipairs(data.blocks) do
    io.write("\n============================================\n")
    io.write("=== Printing segment " .. i .. " of " .. #data.blocks .. " ===\n")
    io.write("============================================\n")
    local success = printBlock(block)
    if success then
      -- Ожидаем окончания только если блок содержал фигуры и реально печатается
      local inactive = printer.getShapeCount()
      if inactive > 0 then
        waitForPrinter()
      end
    else
      io.stderr:write("Process stopped due to config error.\n")
      os.exit(3)
    end
  end
  io.write("\nAll segments of the multi-block model printed successfully!\n")
else
  -- Обычная одноблочная печать
  local success = printBlock(data)
  if success then
    local inactive = printer.getShapeCount()
    if inactive > 0 then
      waitForPrinter()
    end
  end
end
