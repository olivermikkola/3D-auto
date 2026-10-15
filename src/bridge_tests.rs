//! Exercise the real road builder, Lua bindings, meshes and collision queries.
use super::*;
use std::sync::{Arc, Mutex};

fn fixture(case: &str) {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("game");
    let eng = Rc::new(RefCell::new(Engine::new(root.clone(), Arc::new(Mutex::new(audio::Mixer::default())))));
    let lua = unsafe { Lua::unsafe_new_with(StdLib::ALL_SAFE | StdLib::DEBUG, LuaOptions::default()) };
    lua.globals().set("engine", bind(&lua, &eng).unwrap()).unwrap();
    lua.globals().set("__ROOT", root.to_string_lossy().as_ref()).unwrap();
    lua.load(KERNEL).exec().unwrap();
    lua.globals().set("CASE", case).unwrap();
    lua.globals().get::<Table>("package").unwrap().set("path", format!("{}/?.lua", root.display())).unwrap();
    lua.load(include_str!("../game/test/bridge_fixture.lua")).exec().unwrap();
}

#[test]
fn adjacent_road_clearance() {
    fixture("adjacent");
}

#[test]
fn twin_deck_clearance_independent_of_build_order() {
    fixture("twin");
    fixture("twin_reverse");
}

#[test]
fn deck_surface_and_support_are_continuous() {
    fixture("continuity");
}

#[test]
fn true_asphalt_overlap_is_not_hidden() {
    fixture("overlap");
}

#[test]
fn same_level_and_high_crossings_keep_the_deck() {
    fixture("same_level");
    fixture("high_crossing");
}
