# CLAUDE.md

## Project

This is a Roblox game built with Rojo, syncing to Roblox Studio.

## Current active build

**"+1 Mutation: Escaped Experiment"** — an evolution game.

Structure: 4 linear WORLDS in sequence, each with its own lobby (spawn,
store, evolution pedestals, rebirth station). No central hub, no branching
portals -- worlds connect to each other via walk-through screen gateways.

Core loop: player works through a world's linear escape stages by reaching
Win pads, earning Wins (the game's currency) along the way. Wins unlock
that world's evolution forms (12 per world) and fuel Rebirth. Core stat is
"Mutation."

Training plots (lobby, Plot1-8): hitting a plot's dummy grants Mutation at
that plot's multiplier (x1-x70) if the player has unlocked it (free /
rebirth count / gamepass). The rebirth multiplier applies on top. Unlock
rules live in code (TrainingPlots.luau), not on the signs.

## Scope: what Claude works on

Foundational and server-side game logic:
- Game mechanics
- RemoteEvents
- DataStore
- Server-authoritative systems
- Script architecture

## Scope: what Claude does NOT do

The user handles all visuals (models, UI, textures) separately using GPT-6
image generation and Claude Design. Claude builds functional blockout
geometry and logic only -- do not generate placeholder UI, textures, or
visual assets unless explicitly asked.

## Server-authoritative rule

Always follow server-authoritative patterns. Never trust the client for
anything involving Wins, Mutation, evolution-form unlocks, Rebirth, or any
other game state.
