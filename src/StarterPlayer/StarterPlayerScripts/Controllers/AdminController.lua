--!strict
--[[
	AdminController
	---------------
	The client end of Admin Abuse. AdminOpen (the server sends it to admins
	only, after re-checking AdminConfig) builds and opens AdminPanel; nothing
	builds it otherwise. AdminResult is a toast for the admin; AdminBroadcast
	is the filtered banner everyone sees.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local AdminPanel = require(script.Parent.Parent.UI.AdminPanel)
local AnnouncementController = require(script.Parent.AnnouncementController)
local ToastController = require(script.Parent.ToastController)

local AdminController = {}

function AdminController.Init()
	RemoteEvents.AdminOpen.OnClientEvent:Connect(function(payload: any)
		local nextAbuse = if typeof(payload) == "table" and typeof(payload.NextAdminAbuse) == "number"
			then payload.NextAdminAbuse
			else nil
		AdminPanel.Open(nextAbuse)
	end)
	RemoteEvents.AdminResult.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" and typeof(payload.Text) == "string" then
			ToastController.Show(payload.Text, if payload.Ok then "Neutral" else "Error")
		end
	end)
	RemoteEvents.AdminBroadcast.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" and typeof(payload.Text) == "string" then
			AnnouncementController.ShowAdminBroadcast(payload.Text)
		end
	end)
end

return AdminController
