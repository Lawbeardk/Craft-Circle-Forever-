CraftCircleWF_Categories = {
  armorSlots={"Head","Shoulder","Chest","Wrist","Hands","Waist","Legs","Feet","Back"},
  categories={
    Armor={"Cloth","Leather","Mail","Plate","Shields","Librams","Idols","Totems","Sigils","Relics","Miscellaneous"},
    Weapon={"One-Handed Axes","Two-Handed Axes","Bows","Guns","One-Handed Maces","Two-Handed Maces","Polearms","One-Handed Swords","Two-Handed Swords","Staves","Fist Weapons","Daggers","Thrown","Crossbows","Wands","Fishing Poles","Miscellaneous"},
    Consumable={"Potions","Elixirs","Flasks","Food & Drink","Bandages","Scrolls","Item Enhancements","Other"},
    Container={"Bags","Herb Bags","Enchanting Bags","Engineering Bags","Gem Bags","Mining Bags","Leatherworking Bags","Tackle Boxes","Cooking Bags","Other"},
    ["Trade Goods"]={"Cloth","Leather","Metal & Stone","Herbs","Elemental","Enchanting","Jewelcrafting","Parts","Explosives","Devices","Other"},
    Recipe={"Alchemy","Blacksmithing","Cooking","Enchanting","Engineering","First Aid","Fishing","Herbalism","Inscription","Jewelcrafting","Leatherworking","Mining","Skinning","Tailoring","Other"},
    Gem={"Red","Blue","Yellow","Purple","Green","Orange","Meta","Prismatic","Other"},
    Miscellaneous={"Junk","Reagent","Pet","Holiday","Mount","Other"},
    Other={"Alchemy","Blacksmithing","Cooking","Enchanting","Engineering","First Aid","Fishing","Inscription","Jewelcrafting","Leatherworking","Mining","Tailoring","Unknown"},
  },
  icons={Armor="Interface\\Icons\\INV_Chest_Chain",Weapon="Interface\\Icons\\INV_Sword_04",Consumable="Interface\\Icons\\INV_Potion_54",["Trade Goods"]="Interface\\Icons\\INV_Fabric_Linen_01",Recipe="Interface\\Icons\\INV_Scroll_03",Gem="Interface\\Icons\\INV_Misc_Gem_01",Container="Interface\\Icons\\INV_Misc_Bag_08",Quest="Interface\\Icons\\INV_Misc_Note_01",Miscellaneous="Interface\\Icons\\INV_Misc_QuestionMark",Other="Interface\\Icons\\INV_Misc_QuestionMark"}
}
for _,material in ipairs({"Cloth","Leather","Mail","Plate"}) do
  for _,slot in ipairs(CraftCircleWF_Categories.armorSlots) do table.insert(CraftCircleWF_Categories.categories.Armor,material.." - "..slot) end
end
