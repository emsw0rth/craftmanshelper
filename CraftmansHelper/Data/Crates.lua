-- Waylaid Crates: filled with any one bundle from `fills`, then turned in for Merchant's Favor,
-- as often as you like. Key: crate item ID. quality 2 (uncommon) crates give double favor.
local _, ns = ...

-- Merchant's Favor for a common crate, by level.
ns.CRATE_FAVOR = { APPRENTICE = 5, JOURNEYMAN = 10, EXPERT = 15, ARTISAN = 20 }
-- A Forged Delivery Receipt costs this much favor; on any empty crate, it turns in for this reputation.
ns.RECEIPT_FAVOR, ns.RECEIPT_REP = 15, 50

ns.Crates = {
    [248682] = { tier = "APPRENTICE", quality = 1, name = "Apprentice Herbs", fills = {
        { item = 2447, count = 20, name = "Peacebloom" },
        { item = 765, count = 20, name = "Silverleaf" },
        { item = 2449, count = 10, name = "Earthroot" },
        { item = 785, count = 10, name = "Mageroyal" },
        { item = 2450, count = 10, name = "Briarthorn" },
    } },
    [248683] = { tier = "APPRENTICE", quality = 1, name = "Apprentice Ore", fills = {
        { item = 2770, count = 20, name = "Copper Ore" },
        { item = 2771, count = 20, name = "Tin Ore" },
    } },
    [248684] = { tier = "APPRENTICE", quality = 1, name = "Apprentice Textiles", fills = {
        { item = 2589, count = 40, name = "Linen Cloth" },
        { item = 2318, count = 20, name = "Light Leather" },
    } },
    [248685] = { tier = "APPRENTICE", quality = 1, name = "Apprentice Curiosities", fills = {
        { item = 10940, count = 20, name = "Strange Dust" },
        { item = 10939, count = 4, name = "Greater Magic Essence" },
        { item = 10978, count = 6, name = "Small Glimmering Shard" },
        { item = 11084, count = 2, name = "Large Glimmering Shard" },
    } },
    [248686] = { tier = "JOURNEYMAN", quality = 1, name = "Journeyman Herbs", fills = {
        { item = 3820, count = 10, name = "Stranglekelp" },
        { item = 2453, count = 10, name = "Bruiseweed" },
        { item = 3355, count = 10, name = "Wild Steelbloom" },
        { item = 3369, count = 10, name = "Grave Moss" },
        { item = 3356, count = 10, name = "Kingsblood" },
    } },
    [248687] = { tier = "JOURNEYMAN", quality = 1, name = "Journeyman Ore", fills = {
        { item = 2775, count = 10, name = "Silver Ore" },
        { item = 2772, count = 20, name = "Iron Ore" },
    } },
    [248688] = { tier = "JOURNEYMAN", quality = 1, name = "Journeyman Textiles", fills = {
        { item = 2592, count = 20, name = "Wool Cloth" },
        { item = 4306, count = 40, name = "Silk Cloth" },
        { item = 2319, count = 20, name = "Medium Leather" },
    } },
    [248689] = { tier = "JOURNEYMAN", quality = 1, name = "Journeyman Curiosities", fills = {
        { item = 11083, count = 20, name = "Soul Dust" },
        { item = 11082, count = 4, name = "Greater Astral Essence" },
        { item = 11138, count = 6, name = "Small Glowing Shard" },
        { item = 11139, count = 2, name = "Large Glowing Shard" },
    } },
    [248690] = { tier = "EXPERT", quality = 1, name = "Earthly Expert Herbs", fills = {
        { item = 3357, count = 20, name = "Liferoot" },
        { item = 3818, count = 10, name = "Fadeleaf" },
        { item = 3821, count = 10, name = "Goldthorn" },
        { item = 3358, count = 10, name = "Khadgar's Whisker" },
    } },
    [248691] = { tier = "EXPERT", quality = 1, name = "Flowering Expert Herbs", fills = {
        { item = 3819, count = 10, name = "Wintersbite" },
        { item = 4625, count = 10, name = "Firebloom" },
        { item = 8831, count = 20, name = "Purple Lotus" },
        { item = 8836, count = 10, name = "Arthas' Tears" },
    } },
    [248692] = { tier = "EXPERT", quality = 1, name = "Expert Ore", fills = {
        { item = 2776, count = 10, name = "Gold Ore" },
        { item = 3858, count = 20, name = "Mithril Ore" },
    } },
    [248693] = { tier = "EXPERT", quality = 1, name = "Expert Textiles", fills = {
        { item = 4338, count = 40, name = "Mageweave Cloth" },
        { item = 4234, count = 20, name = "Heavy Leather" },
    } },
    [248694] = { tier = "EXPERT", quality = 1, name = "Expert Curiosities", fills = {
        { item = 11137, count = 20, name = "Vision Dust" },
        { item = 11135, count = 4, name = "Greater Mystic Essence" },
        { item = 11177, count = 6, name = "Small Radiant Shard" },
        { item = 11178, count = 2, name = "Large Radiant Shard" },
    } },
    [248695] = { tier = "ARTISAN", quality = 1, name = "Earthly Artisan Herbs", fills = {
        { item = 13464, count = 10, name = "Golden Sansam" },
        { item = 8838, count = 20, name = "Sungrass" },
        { item = 8839, count = 10, name = "Blindweed" },
        { item = 8845, count = 10, name = "Ghost Mushroom" },
        { item = 8846, count = 10, name = "Gromsblood" },
    } },
    [248696] = { tier = "ARTISAN", quality = 1, name = "Flowering Artisan Herbs", fills = {
        { item = 13463, count = 20, name = "Dreamfoil" },
        { item = 13465, count = 20, name = "Mountain Silversage" },
        { item = 13466, count = 20, name = "Plaguebloom" },
        { item = 13467, count = 20, name = "Icecap" },
    } },
    [248697] = { tier = "ARTISAN", quality = 1, name = "Artisan Ore", fills = {
        { item = 7911, count = 10, name = "Truesilver Ore" },
        { item = 10620, count = 20, name = "Thorium Ore" },
        { item = 11370, count = 20, name = "Dark Iron Ore" },
    } },
    [248698] = { tier = "ARTISAN", quality = 1, name = "Artisan Textiles", fills = {
        { item = 14047, count = 40, name = "Runecloth" },
        { item = 4304, count = 20, name = "Thick Leather" },
        { item = 8170, count = 20, name = "Rugged Leather" },
    } },
    [248699] = { tier = "ARTISAN", quality = 1, name = "Artisan Curiosities", fills = {
        { item = 11176, count = 20, name = "Dream Dust" },
        { item = 11175, count = 4, name = "Greater Nether Essence" },
        { item = 14343, count = 6, name = "Small Brilliant Shard" },
        { item = 14344, count = 2, name = "Large Brilliant Shard" },
    } },
    [248702] = { tier = "APPRENTICE", quality = 2, name = "Apprentice Fabrics", fills = {
        { item = 4231, count = 2, name = "Cured Light Hide" },
        { item = 2996, count = 20, name = "Bolt of Linen Cloth" },
    } },
    [248703] = { tier = "APPRENTICE", quality = 2, name = "Apprentice Ingots", fills = {
        { item = 2840, count = 20, name = "Copper Bar" },
        { item = 3576, count = 20, name = "Tin Bar" },
        { item = 2841, count = 10, name = "Bronze Bar" },
    } },
    [248704] = { tier = "APPRENTICE", quality = 2, name = "Apprentice Parts", fills = {
        { item = 4359, count = 16, name = "Handful of Copper Bolts" },
        { item = 4361, count = 16, name = "Copper Tube" },
        { item = 4363, count = 4, name = "Copper Modulator" },
    } },
    [248705] = { tier = "JOURNEYMAN", quality = 2, name = "Journeyman Fabrics", fills = {
        { item = 2997, count = 6, name = "Bolt of Woolen Cloth" },
        { item = 4305, count = 10, name = "Bolt of Silk Cloth" },
        { item = 4233, count = 2, name = "Cured Medium Hide" },
    } },
    [248706] = { tier = "JOURNEYMAN", quality = 2, name = "Journeyman Ingots", fills = {
        { item = 2842, count = 10, name = "Silver Bar" },
        { item = 3575, count = 20, name = "Iron Bar" },
    } },
    [248707] = { tier = "JOURNEYMAN", quality = 2, name = "Journeyman Parts", fills = {
        { item = 4371, count = 8, name = "Bronze Tube" },
        { item = 4375, count = 7, name = "Whirring Bronze Gizmo" },
        { item = 4382, count = 4, name = "Bronze Framework" },
        { item = 10558, count = 45, name = "Gold Power Core" },
    } },
    [248708] = { tier = "EXPERT", quality = 2, name = "Expert Fabrics", fills = {
        { item = 4339, count = 8, name = "Bolt of Mageweave" },
        { item = 4236, count = 2, name = "Cured Heavy Hide" },
    } },
    [248709] = { tier = "EXPERT", quality = 2, name = "Expert Ingots", fills = {
        { item = 3860, count = 20, name = "Mithril Bar" },
        { item = 3859, count = 15, name = "Steel Bar" },
        { item = 3577, count = 10, name = "Gold Bar" },
    } },
    [248710] = { tier = "EXPERT", quality = 2, name = "Expert Parts", fills = {
        { item = 4387, count = 8, name = "Iron Strut" },
        { item = 10559, count = 5, name = "Mithril Tube" },
        { item = 10560, count = 12, name = "Unstable Trigger" },
        { item = 10561, count = 5, name = "Mithril Casing" },
    } },
    [248711] = { tier = "ARTISAN", quality = 2, name = "Artisan Fabrics", fills = {
        { item = 14048, count = 8, name = "Bolt of Runecloth" },
        { item = 8172, count = 2, name = "Cured Thick Hide" },
    } },
    [248712] = { tier = "ARTISAN", quality = 2, name = "Artisan Ingots", fills = {
        { item = 11371, count = 2, name = "Dark Iron Bar" },
        { item = 6037, count = 10, name = "Truesilver Bar" },
        { item = 12359, count = 20, name = "Thorium Bar" },
    } },
    [248713] = { tier = "ARTISAN", quality = 2, name = "Artisan Parts", fills = {
        { item = 15994, count = 5, name = "Thorium Widget" },
        { item = 18631, count = 5, name = "Truesilver Transformer" },
        { item = 16000, count = 2, name = "Thorium Tube" },
    } },
}
