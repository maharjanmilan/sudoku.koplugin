local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local DataStorage = require("datastorage")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LuaSettings = require("luasettings")
local RenderText = require("ui/rendertext")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Font = require("ui/font")
local _ = require("gettext")
local T = require("ffi/util").template

local DISPLAY_PINS_ON_GIVEN = true

local Screen = Device.screen
local DEFAULT_DIFFICULTY = "medium"
local DIFFICULTY_ORDER = { "easy", "medium", "hard" }
local DIFFICULTY_LABELS = {
    easy = _("Easy"),
    medium = _("Medium"),
    hard = _("Hard"),
}

local function emptyGrid()
    local grid = {}
    for r = 1, 9 do
        grid[r] = {}
        for c = 1, 9 do
            grid[r][c] = 0
        end
    end
    return grid
end

local function copyGrid(src)
    local grid = {}
    for r = 1, 9 do
        grid[r] = {}
        for c = 1, 9 do
            grid[r][c] = src[r][c]
        end
    end
    return grid
end

local function emptyNotes()
    local notes = {}
    for r = 1, 9 do
        notes[r] = {}
        for c = 1, 9 do
            notes[r][c] = {}
        end
    end
    return notes
end

local function emptyMarkerGrid()
    local grid = {}
    for r = 1, 9 do
        grid[r] = {}
        for c = 1, 9 do
            grid[r][c] = false
        end
    end
    return grid
end

local function cloneNoteCell(cell)
    if not cell then
        return nil
    end
    local copy = nil
    for digit = 1, 9 do
        if cell[digit] then
            copy = copy or {}
            copy[digit] = true
        end
    end
    return copy
end

local function copyNotes(src)
    local notes = {}
    for r = 1, 9 do
        notes[r] = {}
        for c = 1, 9 do
            local dest_cell = {}
            local source_cell = src and src[r] and src[r][c]
            if type(source_cell) == "table" then
                local had_array_values = false
                for _, digit in ipairs(source_cell) do
                    local d = tonumber(digit)
                    if d and d >= 1 and d <= 9 then
                        dest_cell[d] = true
                        had_array_values = true
                    end
                end
                if not had_array_values then
                    for digit, flag in pairs(source_cell) do
                        local d = tonumber(digit)
                        if d and d >= 1 and d <= 9 and flag then
                            dest_cell[d] = true
                        end
                    end
                end
            end
            notes[r][c] = dest_cell
        end
    end
    return notes
end

local function shuffledDigits()
    local digits = { 1, 2, 3, 4, 5, 6, 7, 8, 9 }
    for i = #digits, 2, -1 do
        local j = math.random(i)
        digits[i], digits[j] = digits[j], digits[i]
    end
    return digits
end

local function isValidPlacement(grid, row, col, value)
    for i = 1, 9 do
        if grid[row][i] == value or grid[i][col] == value then
            return false
        end
    end
    local box_row = math.floor((row - 1) / 3) * 3 + 1
    local box_col = math.floor((col - 1) / 3) * 3 + 1
    for r = box_row, box_row + 2 do
        for c = box_col, box_col + 2 do
            if grid[r][c] == value then
                return false
            end
        end
    end
    return true
end

local function fillBoard(grid, cell)
    if cell > 81 then
        return true
    end
    local row = math.floor((cell - 1) / 9) + 1
    local col = (cell - 1) % 9 + 1
    local numbers = shuffledDigits()
    for _, value in ipairs(numbers) do
        if isValidPlacement(grid, row, col, value) then
            grid[row][col] = value
            if fillBoard(grid, cell + 1) then
                return true
            end
            grid[row][col] = 0
        end
    end
    return false
end

local function generateSolvedBoard()
    local grid = emptyGrid()
    fillBoard(grid, 1)
    return grid
end

local function countSolutions(grid, limit)
    local solutions = 0
    local function search(cell)
        if solutions >= limit then
            return
        end
        if cell > 81 then
            solutions = solutions + 1
            return
        end
        local row = math.floor((cell - 1) / 9) + 1
        local col = (cell - 1) % 9 + 1
        if grid[row][col] ~= 0 then
            search(cell + 1)
            return
        end
        for _, value in ipairs(shuffledDigits()) do
            if isValidPlacement(grid, row, col, value) then
                grid[row][col] = value
                search(cell + 1)
                grid[row][col] = 0
                if solutions >= limit then
                    return
                end
            end
        end
    end
    search(1)
    return solutions
end

local function createPuzzle(solved_grid, difficulty)
    local puzzle = copyGrid(solved_grid)
    local targets = { easy = 35, medium = 45, hard = 53 }
    local removals = targets[difficulty] or targets.medium
    local cells = {}
    for r = 1, 9 do
        for c = 1, 9 do
            cells[#cells + 1] = { r = r, c = c }
        end
    end
    for i = #cells, 2, -1 do
        local j = math.random(i)
        cells[i], cells[j] = cells[j], cells[i]
    end
    local removed = 0
    for _, cell in ipairs(cells) do
        if removed >= removals then
            break
        end
        local row, col = cell.r, cell.c
        if puzzle[row][col] ~= 0 then
            local backup = puzzle[row][col]
            puzzle[row][col] = 0
            local working = copyGrid(puzzle)
            if countSolutions(working, 2) == 1 then
                removed = removed + 1
            else
                puzzle[row][col] = backup
            end
        end
    end
    return puzzle
end

local SudokuBoard = {}
SudokuBoard.__index = SudokuBoard

function SudokuBoard:new()
    local board = {
        puzzle = emptyGrid(),
        solution = emptyGrid(),
        user = emptyGrid(),
        conflicts = emptyGrid(),
        notes = emptyNotes(),
        wrong_marks = emptyMarkerGrid(),
        selected = { row = 1, col = 1 },
        difficulty = DEFAULT_DIFFICULTY,
        reveal_solution = false,
        undo_stack = {},
    }
    setmetatable(board, self)
    board:recalcConflicts()
    return board
end

function SudokuBoard:serialize()
    return {
        puzzle = copyGrid(self.puzzle),
        solution = copyGrid(self.solution),
        user = copyGrid(self.user),
        notes = copyNotes(self.notes),
        wrong_marks = copyGrid(self.wrong_marks),
        selected = { row = self.selected.row, col = self.selected.col },
        difficulty = self.difficulty,
        reveal_solution = self.reveal_solution,
    }
end

function SudokuBoard:load(state)
    if not state or not state.puzzle or not state.solution or not state.user then
        return false
    end
    self.puzzle = copyGrid(state.puzzle)
    self.solution = copyGrid(state.solution)
    self.user = copyGrid(state.user)
    self.notes = copyNotes(state.notes)
    if state.wrong_marks then
        self.wrong_marks = copyGrid(state.wrong_marks)
    else
        self.wrong_marks = emptyMarkerGrid()
    end
    self.difficulty = state.difficulty or DEFAULT_DIFFICULTY
    self.undo_stack = {}
    if state.selected then
        self.selected = {
            row = math.max(1, math.min(9, state.selected.row or 1)),
            col = math.max(1, math.min(9, state.selected.col or 1)),
        }
    else
        self.selected = { row = 1, col = 1 }
    end
    self.reveal_solution = state.reveal_solution or false
    self:recalcConflicts()
    return true
end

function SudokuBoard:generate(difficulty)
    self.difficulty = difficulty or self.difficulty or DEFAULT_DIFFICULTY
    local solution = generateSolvedBoard()
    local puzzle = createPuzzle(solution, self.difficulty)
    self.puzzle = puzzle
    self.solution = solution
    self.user = emptyGrid()
    self.notes = emptyNotes()
    self.wrong_marks = emptyMarkerGrid()
    self.selected = { row = 1, col = 1 }
    self.reveal_solution = false
    self.undo_stack = {}
    self:recalcConflicts()
end

function SudokuBoard:pushUndo(entry)
    if entry then
        self.undo_stack[#self.undo_stack + 1] = entry
    end
end

function SudokuBoard:clearUndoHistory()
    self.undo_stack = {}
end

function SudokuBoard:getWorkingValue(row, col)
    local given = self.puzzle[row][col]
    if given ~= 0 then
        return given
    end
    return self.user[row][col]
end

function SudokuBoard:isGiven(row, col)
    return self.puzzle[row][col] ~= 0
end

local function ensureGridValues(grid)
    for r = 1, 9 do
        grid[r] = grid[r] or {}
        for c = 1, 9 do
            grid[r][c] = grid[r][c] or 0
        end
    end
end

function SudokuBoard:recalcConflicts()
    ensureGridValues(self.conflicts)
    for r = 1, 9 do
        for c = 1, 9 do
            self.conflicts[r][c] = false
        end
    end
    local function markConflicts(cells)
        local map = {}
        for _, cell in ipairs(cells) do
            if cell.value ~= 0 then
                map[cell.value] = map[cell.value] or {}
                table.insert(map[cell.value], cell)
            end
        end
        for _, positions in pairs(map) do
            if #positions > 1 then
                for _, pos in ipairs(positions) do
                    self.conflicts[pos.row][pos.col] = true
                end
            end
        end
    end
    for r = 1, 9 do
        local cells = {}
        for c = 1, 9 do
            cells[#cells + 1] = { row = r, col = c, value = self:getWorkingValue(r, c) }
        end
        markConflicts(cells)
    end
    for c = 1, 9 do
        local cells = {}
        for r = 1, 9 do
            cells[#cells + 1] = { row = r, col = c, value = self:getWorkingValue(r, c) }
        end
        markConflicts(cells)
    end
    for box_row = 0, 2 do
        for box_col = 0, 2 do
            local cells = {}
            for r = 1, 3 do
                for c = 1, 3 do
                    local row = box_row * 3 + r
                    local col = box_col * 3 + c
                    cells[#cells + 1] = { row = row, col = col, value = self:getWorkingValue(row, col) }
                end
            end
            markConflicts(cells)
        end
    end
end

function SudokuBoard:setSelection(row, col)
    self.selected = { row = math.max(1, math.min(9, row)), col = math.max(1, math.min(9, col)) }
end

function SudokuBoard:getSelection()
    return self.selected.row, self.selected.col
end

function SudokuBoard:isShowingSolution()
    return self.reveal_solution
end

function SudokuBoard:toggleSolution()
    self.reveal_solution = not self.reveal_solution
end

function SudokuBoard:setValue(value)
    if self.reveal_solution then
        return false, _("Hide result to keep playing.")
    end
    local row, col = self:getSelection()
    if self:isGiven(row, col) then
        return false, _("This cell is fixed.")
    end
    local prev_value = self.user[row][col]
    local prev_notes = cloneNoteCell(self.notes[row][col])
    local new_value = value or 0

    if prev_value == new_value and not prev_notes then
        if not value then
            return false, _("Cell already empty.")
        end
        return true
    end

    self.user[row][col] = new_value
    self:clearNotes(row, col)
    self:clearWrongMark(row, col)
    self:recalcConflicts()
    if prev_value ~= new_value or prev_notes then
        self:pushUndo{
            type = "value",
            row = row,
            col = col,
            prev_value = prev_value,
            prev_notes = prev_notes,
        }
    end
    return true
end

function SudokuBoard:clearSelection()
    return self:setValue(nil)
end

function SudokuBoard:getDisplayValue(row, col)
    if self.reveal_solution then
        return self.solution[row][col], self:isGiven(row, col)
    end
    if self:isGiven(row, col) then
        return self.puzzle[row][col], true
    end
    local value = self.user[row][col]
    if value == 0 then
        return nil
    end
    return value, false
end

function SudokuBoard:isConflict(row, col)
    return self.conflicts[row][col]
end

function SudokuBoard:clearNotes(row, col)
    if self.notes[row] and self.notes[row][col] then
        self.notes[row][col] = {}
    end
end

function SudokuBoard:getCellNotes(row, col)
    local cell = self.notes[row] and self.notes[row][col]
    if not cell then
        return nil
    end
    for digit = 1, 9 do
        if cell[digit] then
            return cell
        end
    end
    return nil
end

function SudokuBoard:clearWrongMarks()
    for r = 1, 9 do
        for c = 1, 9 do
            self.wrong_marks[r][c] = false
        end
    end
end

function SudokuBoard:clearWrongMark(row, col)
    if self.wrong_marks[row] then
        self.wrong_marks[row][col] = false
    end
end

function SudokuBoard:hasWrongMark(row, col)
    return self.wrong_marks[row] and self.wrong_marks[row][col] or false
end

function SudokuBoard:updateWrongMarks()
    self:clearWrongMarks()
    local has_wrong = false
    for r = 1, 9 do
        for c = 1, 9 do
            local value = self.user[r][c]
            if value ~= 0 and value ~= self.solution[r][c] then
                self.wrong_marks[r][c] = true
                has_wrong = true
            end
        end
    end
    return has_wrong
end

function SudokuBoard:toggleNoteDigit(value)
    if self.reveal_solution then
        return false, _("Hide result to keep playing.")
    end
    local row, col = self:getSelection()
    if self:isGiven(row, col) then
        return false, _("This cell is fixed.")
    end
    if self.user[row][col] ~= 0 then
        return false, _("Clear the cell before adding notes.")
    end
    self.notes[row][col] = self.notes[row][col] or {}
    local prev_cell = cloneNoteCell(self.notes[row][col])
    local was_set = self.notes[row][col][value] and true or false
    if was_set then
        self.notes[row][col][value] = nil
    else
        self.notes[row][col][value] = true
    end
    local now_set = self.notes[row][col][value] and true or false
    if was_set == now_set then
        return true
    end
    self:pushUndo{
        type = "notes",
        row = row,
        col = col,
        prev_notes = prev_cell,
    }
    return true
end

function SudokuBoard:getRemainingCells()
    local remaining = 0
    for r = 1, 9 do
        for c = 1, 9 do
            if self:getWorkingValue(r, c) == 0 then
                remaining = remaining + 1
            end
        end
    end
    return remaining
end

function SudokuBoard:canUndo()
    return self.undo_stack[1] ~= nil
end

function SudokuBoard:undo()
    local entry = table.remove(self.undo_stack)
    if not entry then
        return false, _("Nothing to undo.")
    end
    local row, col = entry.row, entry.col
    if entry.type == "value" then
        self.user[row][col] = entry.prev_value or 0
        self.notes[row][col] = cloneNoteCell(entry.prev_notes) or {}
        self:setSelection(row, col)
        self:recalcConflicts()
        self:clearWrongMark(row, col)
    elseif entry.type == "notes" then
        self.notes[row][col] = cloneNoteCell(entry.prev_notes) or {}
        self:setSelection(row, col)
    end
    return true
end

function SudokuBoard:isSolved()
    if self.reveal_solution then
        return false
    end
    for r = 1, 9 do
        for c = 1, 9 do
            if self:getWorkingValue(r, c) ~= self.solution[r][c] or self.conflicts[r][c] then
                return false
            end
        end
    end
    return true
end

local SudokuBoardWidget = InputContainer:extend{
    board = nil,
}

function SudokuBoardWidget:init()
    self.size = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.82)
    self.dimen = Geom:new{ w = self.size, h = self.size }
    self.paint_rect = Geom:new{ x = 0, y = 0, w = self.size, h = self.size }
    self.number_face = Font:getFace("cfont", math.max(28, math.floor(self.size / 14)))
    self.note_face = Font:getFace("smallinfofont", math.max(16, math.floor(self.size / 28)))
    self.number_face_size = self.number_face.size
    self.number_cell_padding = 0
    self.note_face_size = self.note_face.size
    self.note_mini_padding = 0
    do
        local cell = self.size / 9
        local mini = cell / 3
        local padding = math.max(1, math.floor(mini / 8))
        local safety = math.max(1, math.floor(mini / 18))
        local max_w = math.max(1, math.floor(mini - 2 * padding - safety))
        local max_h = math.max(1, math.floor(mini - 2 * padding - safety))
        local size = self.note_face_size
        while size > 8 do
            local face = Font:getFace("smallinfofont", size)
            local m = RenderText:sizeUtf8Text(0, max_w, face, "8", true, false)
            local h = m.y_bottom - m.y_top
            if m.x <= max_w and h <= max_h then
                local final_size = math.max(8, size - 2)
                self.note_face = Font:getFace("smallinfofont", final_size)
                self.note_face_size = final_size
                self.note_mini_padding = padding
                break
            end
            size = size - 1
        end
    end
    do
        local cell = self.size / 9
        local padding = math.max(2, math.floor(cell / 9))
        local safety = math.max(1, math.floor(cell / 20))
        local max_w = math.max(1, math.floor(cell - 2 * padding - safety))
        local max_h = math.max(1, math.floor(cell - 2 * padding - safety))
        local size = self.number_face_size
        while size > 10 do
            local face = Font:getFace("cfont", size)
            local m = RenderText:sizeUtf8Text(0, max_w, face, "8", true, false)
            local h = m.y_bottom - m.y_top
            if m.x <= max_w and h <= max_h then
                local final_size = math.max(10, size - 4)
                self.number_face = Font:getFace("cfont", final_size)
                self.number_face_size = final_size
                self.number_cell_padding = padding
                break
            end
            size = size - 1
        end
    end
    self.ges_events = {
        Tap = {
            GestureRange:new{
                ges = "tap",
                range = function() return self.paint_rect end,
            }
        }
    }
    if Device:hasKeys() then
        local function addKey(list, key)
            if key then
                list[#list + 1] = { key }
            end
        end
        local function groupKey(name)
            return Device and Device.input and Device.input.group and Device.input.group[name] or nil
        end

        self.key_events = {
            MoveNorth = {},
            MoveSouth = {},
            MoveWest = {},
            MoveEast = {},
            Press = {},
        }

        -- Prefer raw key names (what Kindle/KOReader often emits), but also accept group keys.
        addKey(self.key_events.MoveNorth, "Up")
        addKey(self.key_events.MoveNorth, "CursorUp")
        addKey(self.key_events.MoveNorth, groupKey("Up"))

        addKey(self.key_events.MoveSouth, "Down")
        addKey(self.key_events.MoveSouth, "CursorDown")
        addKey(self.key_events.MoveSouth, groupKey("Down"))

        addKey(self.key_events.MoveWest, "Left")
        addKey(self.key_events.MoveWest, "CursorLeft")
        addKey(self.key_events.MoveWest, groupKey("Left"))

        addKey(self.key_events.MoveEast, "Right")
        addKey(self.key_events.MoveEast, "CursorRight")
        addKey(self.key_events.MoveEast, groupKey("Right"))

        addKey(self.key_events.Press, "Press")
        addKey(self.key_events.Press, "Select")
        addKey(self.key_events.Press, groupKey("Press"))

        -- Add number key handlers if available
        for i = 1, 9 do
            local key_str = tostring(i)
            self.key_events[key_str] = { { key_str } }
        end
    end
end

function SudokuBoardWidget:getCellFromPoint(x, y)
    local rect = self.paint_rect
    local local_x = x - rect.x
    local local_y = y - rect.y
    if local_x < 0 or local_y < 0 or local_x > rect.w or local_y > rect.h then
        return nil
    end
    local cell_size = rect.w / 9
    local col = math.floor(local_x / cell_size) + 1
    local row = math.floor(local_y / cell_size) + 1
    if row < 1 or row > 9 or col < 1 or col > 9 then
        return nil
    end
    return row, col
end

function SudokuBoardWidget:onTap(_, ges)
    if not (self.board and ges and ges.pos) then
        return false
    end
    local row, col = self:getCellFromPoint(ges.pos.x, ges.pos.y)
    if not row then
        return false
    end
    self.board:setSelection(row, col)
    if self.onSelectionChanged then
        self.onSelectionChanged(row, col)
    end
    self:refresh()
    return true
end

function SudokuBoardWidget:onMoveNorth()
    if not self.board then
        return false
    end
    local row, col = self.board:getSelection()
    if row > 1 then
        self.board:setSelection(row - 1, col)
        if self.onSelectionChanged then
            self.onSelectionChanged(row - 1, col)
        end
        self:refresh()
        if self.onStatusUpdate then
            self.onStatusUpdate()
        end
    end
    return true
end

function SudokuBoardWidget:onMoveSouth()
    if not self.board then
        return false
    end
    local row, col = self.board:getSelection()
    if row < 9 then
        self.board:setSelection(row + 1, col)
        if self.onSelectionChanged then
            self.onSelectionChanged(row + 1, col)
        end
        self:refresh()
        if self.onStatusUpdate then
            self.onStatusUpdate()
        end
    end
    return true
end

function SudokuBoardWidget:onMoveWest()
    if not self.board then
        return false
    end
    local row, col = self.board:getSelection()
    if col > 1 then
        self.board:setSelection(row, col - 1)
        if self.onSelectionChanged then
            self.onSelectionChanged(row, col - 1)
        end
        self:refresh()
        if self.onStatusUpdate then
            self.onStatusUpdate()
        end
    end
    return true
end

function SudokuBoardWidget:onMoveEast()
    if not self.board then
        return false
    end
    local row, col = self.board:getSelection()
    if col < 9 then
        self.board:setSelection(row, col + 1)
        if self.onSelectionChanged then
            self.onSelectionChanged(row, col + 1)
        end
        self:refresh()
        if self.onStatusUpdate then
            self.onStatusUpdate()
        end
    end
    return true
end

function SudokuBoardWidget:onPress()
    if not self.board or not self.onErase then
        return false
    end
    self.onErase()
    return true
end

function SudokuBoardWidget:onKeyPress(key)
    if not self.board or not self.onDigit then
        return false
    end
    local digit = tonumber(key)
    if digit and digit >= 1 and digit <= 9 then
        self.onDigit(digit)
        return true
    end
    return false
end

-- Individual number key handlers
function SudokuBoardWidget:on1() if self.onDigit then self.onDigit(1); return true end return false end
function SudokuBoardWidget:on2() if self.onDigit then self.onDigit(2); return true end return false end
function SudokuBoardWidget:on3() if self.onDigit then self.onDigit(3); return true end return false end
function SudokuBoardWidget:on4() if self.onDigit then self.onDigit(4); return true end return false end
function SudokuBoardWidget:on5() if self.onDigit then self.onDigit(5); return true end return false end
function SudokuBoardWidget:on6() if self.onDigit then self.onDigit(6); return true end return false end
function SudokuBoardWidget:on7() if self.onDigit then self.onDigit(7); return true end return false end
function SudokuBoardWidget:on8() if self.onDigit then self.onDigit(8); return true end return false end
function SudokuBoardWidget:on9() if self.onDigit then self.onDigit(9); return true end return false end

function SudokuBoardWidget:refresh()
    local rect = self.paint_rect
    UIManager:setDirty(self, function()
        return "ui", Geom:new{ x = rect.x, y = rect.y, w = rect.w, h = rect.h }
    end)
end

local function drawLine(bb, x, y, w, h, color)
    bb:paintRect(x, y, w, h, color)
end

local function drawDiagonalLine(bb, x, y, length, dx, dy, color, thickness)
    color = color or Blitbuffer.COLOR_BLACK
    thickness = thickness or 1
    length = math.max(0, length)
    for step = 0, length do
        local px = math.floor(x + dx * step)
        local py = math.floor(y + dy * step)
        bb:paintRect(px, py, thickness, thickness, color)
    end
end

function SudokuBoardWidget:paintTo(bb, x, y)
    if not self.board then
        return
    end
    self.paint_rect = Geom:new{ x = x, y = y, w = self.dimen.w, h = self.dimen.h }
    local cell = self.dimen.w / 9
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    local sel_row, sel_col = self.board:getSelection()
    local band_highlight = Blitbuffer.COLOR_GRAY_D
    local cell_highlight = Blitbuffer.COLOR_GRAY
    bb:paintRect(x + (sel_col - 1) * cell, y, cell, self.dimen.h, band_highlight)
    bb:paintRect(x, y + (sel_row - 1) * cell, self.dimen.w, cell, band_highlight)
    bb:paintRect(x + (sel_col - 1) * cell, y + (sel_row - 1) * cell, cell, cell, cell_highlight)
    for i = 0, 9 do
        local thickness = (i % 3 == 0) and Size.line.thick or Size.line.thin
        drawLine(bb, x + math.floor(i * cell), y, thickness, self.dimen.h, Blitbuffer.COLOR_BLACK)
        drawLine(bb, x, y + math.floor(i * cell), self.dimen.w, thickness, Blitbuffer.COLOR_BLACK)
    end
    for row = 1, 9 do
        for col = 1, 9 do
            local value, is_given = self.board:getDisplayValue(row, col)
            if value then
                local cell_x = x + (col - 1) * cell
                local cell_y = y + (row - 1) * cell
                local color
                if self.board:isShowingSolution() and not is_given then
                    color = Blitbuffer.COLOR_GRAY_4
                elseif is_given then
                    color = Blitbuffer.COLOR_BLACK
                else
                    color = Blitbuffer.COLOR_GRAY_2
                end
                if self.board:isConflict(row, col) then
                    color = Blitbuffer.COLOR_RED
                end
                local text = tostring(value)
                local cell_padding = self.number_cell_padding or 0
                local cell_inner = math.max(1, math.floor(cell - 2 * cell_padding))
                local metrics = RenderText:sizeUtf8Text(0, cell_inner, self.number_face, text, true, false)
                local text_w = metrics.x
                local baseline = cell_y + cell_padding + math.floor((cell_inner + metrics.y_top - metrics.y_bottom) / 2)
                local text_x = cell_x + cell_padding + math.floor((cell_inner - text_w) / 2)
                RenderText:renderUtf8Text(bb, text_x, baseline, self.number_face, text, true, false, color)
                if is_given and DISPLAY_PINS_ON_GIVEN then
                    local dot = math.max(1, math.floor(cell / 18))
                    local padding = math.max(1, math.floor(cell / 20))
                    local dot_color = Blitbuffer.COLOR_GRAY_4
                    bb:paintRect(cell_x + padding, cell_y + padding, dot, dot, dot_color)
                    bb:paintRect(cell_x + cell - padding - dot, cell_y + padding, dot, dot, dot_color)
                    bb:paintRect(cell_x + padding, cell_y + cell - padding - dot, dot, dot, dot_color)
                    bb:paintRect(cell_x + cell - padding - dot, cell_y + cell - padding - dot, dot, dot, dot_color)
                elseif self.board:hasWrongMark(row, col) then
                    local padding = math.max(1, math.floor(cell / 12))
                    local diag_len = math.max(0, math.floor(cell - padding * 2))
                    local cross_thickness = math.max(2, math.floor(cell / 18))
                    drawDiagonalLine(bb, cell_x + padding, cell_y + padding, diag_len, 1, 1, Blitbuffer.COLOR_BLACK, cross_thickness)
                    drawDiagonalLine(bb, cell_x + padding, cell_y + cell - padding, diag_len, 1, -1, Blitbuffer.COLOR_BLACK, cross_thickness)
                end
            else
                local notes = self.board:getCellNotes(row, col)
                if notes then
                    local mini = cell / 3
                    local mini_padding = self.note_mini_padding or 0
                    local mini_inner = math.max(1, math.floor(mini - 2 * mini_padding))
                    for digit = 1, 9 do
                        if notes[digit] then
                            local mini_col = (digit - 1) % 3
                            local mini_row = math.floor((digit - 1) / 3)
                            local mini_x = x + (col - 1) * cell + mini_col * mini
                            local mini_y = y + (row - 1) * cell + mini_row * mini
                            local note_text = tostring(digit)
                            local note_metrics = RenderText:sizeUtf8Text(0, mini_inner, self.note_face, note_text, true, false)
                            local note_baseline = mini_y + mini_padding + math.floor((mini_inner + note_metrics.y_top - note_metrics.y_bottom) / 2)
                            local note_x = mini_x + mini_padding + math.floor((mini_inner - note_metrics.x) / 2)
                            RenderText:renderUtf8Text(bb, note_x, note_baseline, self.note_face, note_text, true, false, Blitbuffer.COLOR_GRAY_4)
                        end
                    end
                end
            end
        end
    end
end

local SudokuScreen = InputContainer:extend{}

local function normalizeKeyEvent(key)
    -- KOReader may pass a string key name OR a table/event object depending on backend.
    if type(key) == "table" then
        local v = key.key or key.name or key.code or key.sym or key.keycode or key.key_code or key.keyname or key.key_name or key[1]
        if type(v) == "table" then
            v = v.key or v.name or v.code or v.sym or v.keycode or v.key_name or v[1]
        end
        return v
    end
    return key
end

function SudokuScreen:onKeyPress(key)
    local k = normalizeKeyEvent(key)
    
    if not (Device:hasKeys() and self.board and self.board_widget) then
        return false
    end

    local group = Device and Device.input and Device.input.group or {}

    -- 5-way navigation: always moves the grid selection
    if k == "Up" or k == "up" or k == "CursorUp" or k == "cursorup" or k == "KP8" or (group.Up and k == group.Up) then
        return self:onMoveNorth()
    elseif k == "Down" or k == "down" or k == "CursorDown" or k == "cursordown" or k == "KP2" or (group.Down and k == group.Down) then
        return self:onMoveSouth()
    elseif k == "Left" or k == "left" or k == "CursorLeft" or k == "cursorleft" or k == "KP4" or (group.Left and k == group.Left) then
        return self:onMoveWest()
    elseif k == "Right" or k == "right" or k == "CursorRight" or k == "cursorright" or k == "KP6" or (group.Right and k == group.Right) then
        return self:onMoveEast()
    end

    -- Page keys: cycle active digit (Kindle 4 has no number keys)
    if k == "PgFwd" or k == "Next" or k == "NextPage" or k == "PageFwd" or
       k == "RPgFwd" or k == "LPgFwd" or (group.PgFwd and k == group.PgFwd) then
        return self:onDigitNext()
    elseif k == "PgBack" or k == "Prev" or k == "PrevPage" or k == "PageBack" or
           k == "RPgBack" or k == "LPgBack" or (group.PgBack and k == group.PgBack) then
        return self:onDigitPrev()
    end

    -- Center press: place active digit (or toggle note digit if note_mode)
    if k == "Press" or k == "Select" or (group.Press and k == group.Press) then
        return self:onPress()
    end

    -- Home key: toggle note mode (Kindle 4 has a Home key that reliably emits an event)
    if k == "Home" or (group.Home and k == group.Home) then
        return self:onToggleNote()
    end

    -- Back/Menu: ALWAYS provide an exit route on key devices.
    -- Back closes immediately; Menu opens the command menu.
    if k == "Back" or k == "Escape" or (group.Back and k == group.Back) then
        return self:onCloseKey()
    elseif k == "Menu" then
        return self:onOpenMenu()
    end

    -- If a device actually has number keys, still support them
    local digit = tonumber(k)
    if digit and digit >= 1 and digit <= 9 then
        self.active_digit = digit
        self:updateStatus()
        return true
    end

    return false
end

-- Override handleKey to intercept arrow keys before child widgets (like ButtonTable)
function SudokuScreen:handleKey(key)
    local k = normalizeKeyEvent(key)
    if Device:hasKeys() and self.board and self.board_widget then
        local group = Device and Device.input and Device.input.group or {}
        -- Always intercept arrow keys for board navigation, prevent ButtonTable from handling them
        if k == "Up" or k == "up" or k == "CursorUp" or k == "cursorup" or k == "KP8" or (group.Up and k == group.Up) then
            if self:onMoveNorth() then return true end
        elseif k == "Down" or k == "down" or k == "CursorDown" or k == "cursordown" or k == "KP2" or (group.Down and k == group.Down) then
            if self:onMoveSouth() then return true end
        elseif k == "Left" or k == "left" or k == "CursorLeft" or k == "cursorleft" or k == "KP4" or (group.Left and k == group.Left) then
            if self:onMoveWest() then return true end
        elseif k == "Right" or k == "right" or k == "CursorRight" or k == "cursorright" or k == "KP6" or (group.Right and k == group.Right) then
            if self:onMoveEast() then return true end
        elseif k == "PgFwd" or k == "Next" or k == "NextPage" or k == "PageFwd" or
               k == "RPgFwd" or k == "LPgFwd" or (group.PgFwd and k == group.PgFwd) then
            if self:onDigitNext() then return true end
        elseif k == "PgBack" or k == "Prev" or k == "PrevPage" or k == "PageBack" or
               k == "RPgBack" or k == "LPgBack" or (group.PgBack and k == group.PgBack) then
            if self:onDigitPrev() then return true end
        elseif k == "Press" or k == "Select" or (group.Press and k == group.Press) then
            if self:onPress() then return true end
        elseif k == "Home" or (group.Home and k == group.Home) then
            if self:onToggleNote() then return true end
        elseif k == "Back" or k == "Escape" or (group.Back and k == group.Back) then
            if self:onCloseKey() then return true end
        elseif k == "Menu" then
            if self:onOpenMenu() then return true end
        end
    end
    -- For other keys, use default handling
    return InputContainer.handleKey(self, key)
end

function SudokuScreen:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.covers_fullscreen = true
    self.vertical_align = "center"
    self.note_mode = false
    self.active_digit = 1
    self._closed = false
    self.undo_button = nil
    if Device:hasKeys() then
        local function addKey(list, key)
            if key then
                list[#list + 1] = { key }
            end
        end
        local function groupKey(name)
            return Device and Device.input and Device.input.group and Device.input.group[name] or nil
        end

        self.key_events = {
            OpenMenu = {},
            MoveNorth = {},
            MoveSouth = {},
            MoveWest = {},
            MoveEast = {},
            DigitNext = {},
            DigitPrev = {},
            Press = {},
            ToggleNote = {},
        }

        -- On key-only devices, Back opens the command menu (Close is in that menu)
        addKey(self.key_events.OpenMenu, groupKey("Back"))
        addKey(self.key_events.OpenMenu, "Back")
        addKey(self.key_events.OpenMenu, "Menu")
        addKey(self.key_events.OpenMenu, "Escape")

        addKey(self.key_events.MoveNorth, "Up")
        addKey(self.key_events.MoveNorth, "CursorUp")
        addKey(self.key_events.MoveNorth, groupKey("Up"))

        addKey(self.key_events.MoveSouth, "Down")
        addKey(self.key_events.MoveSouth, "CursorDown")
        addKey(self.key_events.MoveSouth, groupKey("Down"))

        addKey(self.key_events.MoveWest, "Left")
        addKey(self.key_events.MoveWest, "CursorLeft")
        addKey(self.key_events.MoveWest, groupKey("Left"))

        addKey(self.key_events.MoveEast, "Right")
        addKey(self.key_events.MoveEast, "CursorRight")
        addKey(self.key_events.MoveEast, groupKey("Right"))

        -- Page keys cycle the active digit (1..9)
        addKey(self.key_events.DigitNext, "PgFwd")
        addKey(self.key_events.DigitNext, "Next")
        addKey(self.key_events.DigitNext, "NextPage")
        addKey(self.key_events.DigitNext, "PageFwd")
        addKey(self.key_events.DigitNext, "RPgFwd")
        addKey(self.key_events.DigitNext, "LPgFwd")
        addKey(self.key_events.DigitNext, groupKey("PgFwd"))

        addKey(self.key_events.DigitPrev, "PgBack")
        addKey(self.key_events.DigitPrev, "Prev")
        addKey(self.key_events.DigitPrev, "PrevPage")
        addKey(self.key_events.DigitPrev, "PageBack")
        addKey(self.key_events.DigitPrev, "RPgBack")
        addKey(self.key_events.DigitPrev, "LPgBack")
        addKey(self.key_events.DigitPrev, groupKey("PgBack"))

        addKey(self.key_events.Press, "Press")
        addKey(self.key_events.Press, "Select")
        addKey(self.key_events.Press, groupKey("Press"))

        -- Home key toggles Note mode on Kindle 4.
        addKey(self.key_events.ToggleNote, "Home")
        addKey(self.key_events.ToggleNote, groupKey("Home"))

        -- Add number key handlers if available
        for i = 1, 9 do
            local key_str = tostring(i)
            self.key_events[key_str] = { { key_str } }
        end
    end
    if Device:hasKeys() then
        self.header_text = TextWidget:new{
            text = "",
            face = Font:getFace("smallinfofont"),
        }
    end
    self.status_text = TextWidget:new{
        text = Device:hasKeys()
            and _("5-way: move. Page keys: change digit. Center: place digit. Home: Note. Back: menu.")
            or _("Tap a cell, then pick a number."),
        face = Font:getFace("smallinfofont"),
    }
    self.board_widget = SudokuBoardWidget:new{
        board = self.board,
        onSelectionChanged = function()
            self:updateStatus()
        end,
        onDigit = function(digit)
            self:onDigit(digit)
        end,
        onErase = function()
            self:onErase()
        end,
        onStatusUpdate = function()
            self:updateStatus()
        end,
    }
    -- If the last saved state had "show result" enabled, hide it on entry for key-only gameplay.
    if self.board and self.board.reveal_solution then
        self.board.reveal_solution = false
    end
    self:buildLayout()
    self:updateHeader()
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
end

function SudokuScreen:onCloseKey()
    -- Hard exit path for key-only devices.
    if self._closed then
        return true
    end
    self._closed = true
    self:onClose()
    UIManager:close(self)
    UIManager:setDirty(nil, "full")
    return true
end

function SudokuScreen:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    local content_size = self.layout:getSize()
    local offset_x = x + math.floor((self.dimen.w - content_size.w) / 2)
    local offset_y = y
    if self.vertical_align == "center" then
        offset_y = offset_y + math.floor((self.dimen.h - content_size.h) / 2)
    end
    self.layout:paintTo(bb, offset_x, offset_y)
end

function SudokuScreen:buildLayout()
    local board_frame = FrameContainer:new{
        padding = Size.padding.large,
        margin = Size.margin.default,
        self.board_widget,
    }
    local top_buttons, keypad
    if Device:hasKeys() then
        -- Key-only devices: avoid ButtonTable (it captures arrow keys).
        -- Use Back to open an action menu instead.
        self.show_result_button = nil
        self.difficulty_button = nil
        self.note_button = nil
        self.undo_button = nil
    else
        top_buttons = ButtonTable:new{
            shrink_unneeded_width = true,
            width = math.floor(Screen:getWidth() * 0.9),
            buttons = {
                {
                    {
                        text = _("New game"),
                        callback = function()
                            self:onNewGame()
                        end,
                    },
                    {
                        id = "difficulty_button",
                        text = self:getDifficultyButtonText(),
                        callback = function()
                            self:openDifficultyMenu()
                        end,
                    },
                    {
                        id = "show_result",
                        text = _("Show result"),
                        callback = function()
                            self:toggleSolution()
                        end,
                    },
                    {
                        text = _("Close"),
                        callback = function()
                            self:onClose()
                            UIManager:close(self)
                            UIManager:setDirty(nil, "full")
                        end,
                    },
                },
            },
        }
        self.show_result_button = top_buttons:getButtonById("show_result")
        self.difficulty_button = top_buttons:getButtonById("difficulty_button")

        local keypad_rows = {}
        local value = 1
        for _ = 1, 3 do
            local row = {}
            for _ = 1, 3 do
                local digit = value
                row[#row + 1] = {
                    text = tostring(digit),
                    callback = function()
                        self:onDigit(digit)
                    end,
                }
                value = value + 1
            end
            keypad_rows[#keypad_rows + 1] = row
        end
        keypad_rows[#keypad_rows + 1] = {
            {
                id = "note_button",
                text = self:getNoteButtonText(),
                callback = function()
                    self:toggleNoteMode()
                end,
            },
            {
                text = _("Erase"),
                callback = function()
                    self:onErase()
                end,
            },
            {
                text = _("Check"),
                callback = function()
                    self:checkProgress()
                end,
            },
            {
                id = "undo_button",
                text = _("Undo"),
                callback = function()
                    self:onUndo()
                end,
            },
        }
        keypad = ButtonTable:new{
            width = math.floor(Screen:getWidth() * 0.75),
            shrink_unneeded_width = true,
            buttons = keypad_rows,
        }
        self.note_button = keypad:getButtonById("note_button")
        self.undo_button = keypad:getButtonById("undo_button")
    end
    if Device:hasKeys() then
        self.layout = VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.header_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            board_frame,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
        }
    else
        self.layout = VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = Size.span.vertical_large },
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            board_frame,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            keypad,
            VerticalSpan:new{ width = Size.span.vertical_large },
        }
    end
    self[1] = self.layout
    self:ensureShowButtonState()
    self:updateNoteButton()
    self:updateUndoButton()
    self:updateDifficultyButton()
    self:updateStatus()
end

function SudokuScreen:getNoteButtonText()
    return self.note_mode and _("Note: On") or _("Note: Off")
end

function SudokuScreen:updateNoteButton()
    if not self.note_button then
        return
    end
    local width = self.note_button.width
    self.note_button:setText(self:getNoteButtonText(), width)
end

function SudokuScreen:updateUndoButton()
    if not self.undo_button then
        return
    end
    self.undo_button:enableDisable(self.board:canUndo())
end

function SudokuScreen:toggleNoteMode()
    self.note_mode = not self.note_mode
    self:updateNoteButton()
    self:updateHeader()
    self:updateStatus(self.note_mode and _("Note mode enabled.") or _("Note mode disabled."))
end

function SudokuScreen:getDifficultyButtonText()
    local label = DIFFICULTY_LABELS[self.board.difficulty] or self.board.difficulty
    return T(_("Difficulty: %1"), label)
end

function SudokuScreen:updateDifficultyButton()
    if not self.difficulty_button then
        return
    end
    local width = self.difficulty_button.width
    self.difficulty_button:setText(self:getDifficultyButtonText(), width)
end

function SudokuScreen:openDifficultyMenu()
    local menu
    local function selectDifficulty(level)
        if level ~= self.board.difficulty then
            self.board:generate(level)
            self.plugin:saveState()
            self.board_widget:refresh()
            self:ensureShowButtonState()
            self:updateStatus(T(_("Started a %1 game."), DIFFICULTY_LABELS[level] or level))
        else
            self:updateStatus()
        end
        self:updateDifficultyButton()
        self:updateHeader()
        if menu then
            UIManager:close(menu)
        end
        return true
    end

    local items = {}
    for _, level in ipairs(DIFFICULTY_ORDER) do
        items[#items + 1] = {
            text = DIFFICULTY_LABELS[level] or level,
            checked = (level == self.board.difficulty),
            callback = function()
                return selectDifficulty(level)
            end,
        }
    end

    menu = Menu:new{
        title = _("Select difficulty"),
        item_table = items,
        width = math.floor(Screen:getWidth() * 0.7),
        height = math.floor(Screen:getHeight() * 0.9),
        disable_footer_padding = true,
        show_parent = self,
    }
    UIManager:show(menu)
end

function SudokuScreen:getHeaderText()
    local difficulty_label = DIFFICULTY_LABELS[self.board.difficulty] or self.board.difficulty or ""
    local note_label = self.note_mode and _("Note: On") or _("Note: Off")
    return T(_("Difficulty: %1   %2"), difficulty_label, note_label)
end

function SudokuScreen:updateHeader()
    if not (Device:hasKeys() and self.header_text) then
        return
    end
    self.header_text:setText(self:getHeaderText())
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
end

function SudokuScreen:onToggleNote()
    self:toggleNoteMode()
    return true
end

function SudokuScreen:updateStatus(message)
    local status
    if message then
        status = message
    else
        local remaining = self.board:getRemainingCells()
        local row, col = self.board:getSelection()
        status = T(_("Selected: %1,%2  ·  Empty cells: %3"), row, col, remaining)
        if Device:hasKeys() then
            status = status .. "\n" .. T(_("Digit: %1"), self.active_digit or 1)
        end
        if self.board:isShowingSolution() then
            status = status .. "\n" .. _("Result is being shown; editing is disabled.")
        elseif self.board:isSolved() then
            status = _("Congratulations! Puzzle solved.")
        -- elseif self.note_mode then
        --     status = status .. "\n" .. _("Note mode is ON.")
        end
    end
    self.status_text:setText(status)
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
end

function SudokuScreen:onDigitNext()
    self.active_digit = (self.active_digit or 1) + 1
    if self.active_digit > 9 then
        self.active_digit = 1
    end
    self:updateStatus()
    return true
end

function SudokuScreen:onDigitPrev()
    self.active_digit = (self.active_digit or 1) - 1
    if self.active_digit < 1 then
        self.active_digit = 9
    end
    self:updateStatus()
    return true
end

function SudokuScreen:onDigit(value)
    if self.note_mode then
        local ok, err = self.board:toggleNoteDigit(value)
        if not ok then
            self:updateStatus(err)
            return
        end
        self.board_widget:refresh()
        self:updateStatus()
        self.plugin:saveState()
        self:updateUndoButton()
        return
    end
    local ok, err = self.board:setValue(value)
    if not ok then
        self:updateStatus(err)
        return
    end
    self.board_widget:refresh()
    self:updateStatus()
    self.plugin:saveState()
    self:updateUndoButton()
    if self.board:isSolved() then
        UIManager:show(InfoMessage:new{ text = _("Puzzle complete!"), timeout = 4 })
    end
end

function SudokuScreen:onErase()
    local row, col = self.board:getSelection()
    self.board:clearNotes(row, col)
    local ok, err = self.board:clearSelection()
    if not ok then
        self:updateStatus(err)
        return
    end
    self.board_widget:refresh()
    self:updateStatus()
    self.plugin:saveState()
    self:updateUndoButton()
end

function SudokuScreen:onNewGame()
    self.board:generate(self.board.difficulty)
    self.plugin:saveState()
    self.board_widget:refresh()
    self:ensureShowButtonState()
    self:updateUndoButton()
    self:updateStatus(_("Started a new game."))
end

function SudokuScreen:toggleSolution()
    self.board:toggleSolution()
    self.plugin:saveState()
    self.board_widget:refresh()
    self:ensureShowButtonState()
    self:updateStatus(self.board:isShowingSolution() and _("Showing the solution.") or nil)
end

function SudokuScreen:ensureShowButtonState()
    if not self.show_result_button then
        return
    end
    local text = self.board:isShowingSolution() and _("Hide result") or _("Show result")
    local width = self.show_result_button.width
    self.show_result_button:setText(text, width)
end

function SudokuScreen:checkProgress()
    self.board:updateWrongMarks()
    self.board_widget:refresh()
    self.plugin:saveState()
    if self.board:isSolved() then
        self:updateStatus(_("Everything looks good!"))
    elseif self.board:getRemainingCells() == 0 then
        self:updateStatus(_("There are mistakes highlighted in red."))
    else
        self:updateStatus(_("Keep going!"))
    end
end

function SudokuScreen:onClose()
    self.plugin:saveState()
    self.plugin:onScreenClosed()
end

function SudokuScreen:onUndo()
    local ok, err = self.board:undo()
    if not ok then
        self:updateStatus(err)
        return
    end
    self.board_widget:refresh()
    self:updateStatus(_("Last move undone."))
    self.plugin:saveState()
    self:updateUndoButton()
end

function SudokuScreen:onMoveNorth()
    -- Always handle arrow keys for board navigation, prevent ButtonTable from handling them
    if self.board and self.board_widget then
        local row, col = self.board:getSelection()
        if row > 1 then
            self.board:setSelection(row - 1, col)
            if self.board_widget.onSelectionChanged then
                self.board_widget.onSelectionChanged(row - 1, col)
            end
            self.board_widget:refresh()
            self:updateStatus()
        end
        UIManager:setDirty(nil, "partial")
        return true
    end
    return false
end

function SudokuScreen:onMoveSouth()
    -- Always handle arrow keys for board navigation, prevent ButtonTable from handling them
    if self.board and self.board_widget then
        local row, col = self.board:getSelection()
        if row < 9 then
            self.board:setSelection(row + 1, col)
            if self.board_widget.onSelectionChanged then
                self.board_widget.onSelectionChanged(row + 1, col)
            end
            self.board_widget:refresh()
            self:updateStatus()
        end
        UIManager:setDirty(nil, "partial")
        return true
    end
    return false
end

function SudokuScreen:onMoveWest()
    -- Always handle arrow keys for board navigation, prevent ButtonTable from handling them
    if self.board and self.board_widget then
        local row, col = self.board:getSelection()
        if col > 1 then
            self.board:setSelection(row, col - 1)
            if self.board_widget.onSelectionChanged then
                self.board_widget.onSelectionChanged(row, col - 1)
            end
            self.board_widget:refresh()
            self:updateStatus()
        end
        UIManager:setDirty(nil, "partial")
        return true
    end
    return false
end

function SudokuScreen:onMoveEast()
    -- Always handle arrow keys for board navigation, prevent ButtonTable from handling them
    if self.board and self.board_widget then
        local row, col = self.board:getSelection()
        if col < 9 then
            self.board:setSelection(row, col + 1)
            if self.board_widget.onSelectionChanged then
                self.board_widget.onSelectionChanged(row, col + 1)
            end
            self.board_widget:refresh()
            self:updateStatus()
        end
        UIManager:setDirty(nil, "partial")
        return true
    end
    return false
end

function SudokuScreen:onPress()
    -- Center key: place the active digit (or toggle a note digit if note_mode)
    local d = self.active_digit or 1
    self:onDigit(d)
    return true
end

function SudokuScreen:onOpenMenu()
    local menu
    local items = {
        { text = _("New game"), callback = function() self:onNewGame(); if menu then UIManager:close(menu) end; return true end },
        { text = _("Difficulty"), callback = function() self:openDifficultyMenu(); if menu then UIManager:close(menu) end; return true end },
        { text = self.board:isShowingSolution() and _("Hide result") or _("Show result"), callback = function() self:toggleSolution(); if menu then UIManager:close(menu) end; return true end },
        { text = self.note_mode and _("Note: Off") or _("Note: On"), callback = function() self:toggleNoteMode(); if menu then UIManager:close(menu) end; return true end },
        { text = _("Erase cell"), callback = function() self:onErase(); if menu then UIManager:close(menu) end; return true end },
        { text = _("Check"), callback = function() self:checkProgress(); if menu then UIManager:close(menu) end; return true end },
        { text = _("Undo"), enabled = self.board:canUndo(), callback = function() self:onUndo(); if menu then UIManager:close(menu) end; return true end },
        { text = _("Close"), callback = function() self:onClose(); UIManager:close(self); UIManager:setDirty(nil, "full"); if menu then UIManager:close(menu) end; return true end },
    }
    menu = Menu:new{
        title = _("Sudoku"),
        item_table = items,
        width = math.floor(Screen:getWidth() * 0.8),
        height = math.floor(Screen:getHeight() * 0.9),
        disable_footer_padding = true,
        show_parent = self,
    }
    UIManager:show(menu)
    return true
end


-- Individual number key handlers for direct key press
function SudokuScreen:on1() self:onDigit(1); return true end
function SudokuScreen:on2() self:onDigit(2); return true end
function SudokuScreen:on3() self:onDigit(3); return true end
function SudokuScreen:on4() self:onDigit(4); return true end
function SudokuScreen:on5() self:onDigit(5); return true end
function SudokuScreen:on6() self:onDigit(6); return true end
function SudokuScreen:on7() self:onDigit(7); return true end
function SudokuScreen:on8() self:onDigit(8); return true end
function SudokuScreen:on9() self:onDigit(9); return true end

local Sudoku = WidgetContainer:extend{
    name = "sudoku",
    is_doc_only = false,
}

function Sudoku:ensureSettings()
    if not self.settings_file then
        self.settings_file = DataStorage:getSettingsDir() .. "/sudoku.lua"
    end
    if not self.settings then
        self.settings = LuaSettings:open(self.settings_file)
    end
end

function Sudoku:init()
    self:ensureSettings()
    self.ui.menu:registerToMainMenu(self)
end

function Sudoku:addToMainMenu(menu_items)
    menu_items.sudoku = {
        text = _("Sudoku"),
        sorting_hint = "tools",
        callback = function()
            self:showGame()
        end,
    }
end

function Sudoku:getBoard()
    if not self.board then
        self:ensureSettings()
        self.board = SudokuBoard:new()
        local state = self.settings:readSetting("state")
        if not self.board:load(state) then
            self.board:generate(DEFAULT_DIFFICULTY)
        end
    end
    return self.board
end

function Sudoku:saveState()
    if not self.board then
        return
    end
    self:ensureSettings()
    self.settings:saveSetting("state", self.board:serialize())
    self.settings:flush()
end

function Sudoku:showGame()
    if self.screen then
        return
    end
    self.screen = SudokuScreen:new{
        board = self:getBoard(),
        plugin = self,
    }
    UIManager:show(self.screen)
end

function Sudoku:onScreenClosed()
    self.screen = nil
end

return Sudoku

