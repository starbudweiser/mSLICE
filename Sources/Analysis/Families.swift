// mSLICE — familles lisibles de scènes et de sons.
//
// macOS reconnaît 1 303 types d'images (Vision) et 303 types de sons (SoundAnalysis). Pour l'utilisateur, on les regroupe en familles
// (« Feu et flammes », « Rires », « Coups de feu »…), traduites dans les quatre langues. Les étiquettes brutes restent interrogeables
// par les agents (`label:` / `sound_label:`). Un essai (`--selftest-analysis`) vérifie que chaque étiquette citée existe bien dans macOS.
import Foundation

struct Family: Sendable {
    let id: String
    let symbol: String                 // SF Symbol (rendu monochrome)
    let names: [String]                // fr, en, es, it
    let labels: [String]
    var name: String { names[L.lang.rawValue] }
}

enum SceneFamilies {
    private static func f(_ id: String, _ symbol: String, _ names: String, _ labels: String) -> Family {
        Family(id: id, symbol: symbol, names: names.components(separatedBy: "|"), labels: labels.split(separator: " ").map(String.init))
    }

    static let all: [Family] = [
        f("people", "person.2", "Personnes|People|Personas|Persone", "people adult teen child baby"),
        f("crowd", "person.3", "Foule et public|Crowd and audience|Multitud y público|Folla e pubblico", "crowd concert parade bleachers stadium auditorium conference arena fairground carnival"),
        f("clothing", "tshirt", "Vêtements et costumes|Clothing and costumes|Ropa y disfraces|Abiti e costumi",
          "costume clothing suit tuxedo necktie bowtie jacket gown hoodie cloak poncho scarf hat headgear sunhat fedora beanie cowboy_hat baseball_hat sombrero kilt kimono sari bathrobe apron glove glove_other mitten footwear shoes boot sneaker sandal high_heel loafer moccasin ski_boot sock jeans swimsuit wetsuit leotard sunglasses eyeglasses jewelry military_uniform safety_vest tiara mask"),
        f("medical", "cross.case", "Médical|Medical|Médico|Medico", "lab_coat hospital stethoscope syringe medicine stretcher thermometer wheelchair crutch microscope pacifier"),
        f("documents", "book", "Livres et documents|Books and documents|Libros y documentos|Libri e documenti",
          "book bookshelf library document printed_page magazine newspaper flipchart chalkboard whiteboard handwriting diagram chart receipt envelope ticket sticky_note checkbook calendar map passport coupon record"),
        f("screens", "display", "Écrans et appareils|Screens and devices|Pantallas y dispositivos|Schermi e dispositivi",
          "computer laptop computer_monitor computer_keyboard computer_mouse computer_tower television screenshot gamepad videogame joystick phone payphone consumer_electronics stereo headphones speakers_music camera tripod circuit_board keypad"),
        f("office", "briefcase", "Bureau|Office|Oficina|Ufficio", "desk cubicle office_supplies swivel_chair calculator printer briefcase pen"),
        f("school", "graduationcap", "École|School|Escuela|Scuola", "classroom graduation backpack chalkboard"),
        f("doors", "door.left.hand.closed", "Portes, fenêtres, escaliers|Doors, windows, stairs|Puertas, ventanas, escaleras|Porte, finestre, scale", "door window curtain elevator escalator stairs portal porthole"),
        f("indoors", "sofa", "Intérieur|Indoors|Interior|Interni",
          "interior_room living_room bedroom bedroom dining_room bathroom bathroom_room furniture sofa armchair chaise bed bedding pillow table chair chair_other stool bench cabinet closet lamp chandelier fireplace shower bath washbasin toilet_seat high_chair folding_chair crib clothesline"),
        f("kitchen", "refrigerator", "Cuisine|Kitchen|Cocina|Cucina", "kitchen kitchen_room kitchen_countertop kitchen_sink kitchen_oven kitchen_faucet refrigerator stove dishwasher microwave toaster toaster_oven cookware pot_cooking pan cutting_board utensil tableware kettle teapot blender"),
        f("food", "fork.knife", "Nourriture|Food|Comida|Cibo",
          "food meat beef bacon bagel baked_goods baklava bread brownie bruschetta burrito butter cake cake_regular candy cereal cheese cheesecake chocolate cookie croissant crepe cupcake curry dessert donut dumpling egg falafel fries fruit fried_chicken gingerbread hamburger hotdog ice_cream meatball muffin naan nachos omelet pancake pasta pastry pie pizza popcorn ramen rice risotto salad sandwich sausage soup spaghetti steak sushi taco tiramisu tortilla vegetable waffle yogurt apple banana berry strawberry oranges lemon grape peach pear pineapple watermelon tomato potato carrot onion corn mushroom salami ham pepperoni seafood poultry"),
        f("drinks", "cup.and.saucer", "Boissons|Drinks|Bebidas|Bevande", "drink wine wine_bottle red_wine white_wine beer cocktail coffee coffee_bean tea_drink juice soda milkshake smoothie liquor margarita martini mojito sangria sparkling_wine tequila bottle drinking_glass cup mug keg decanter bubble_tea"),
        f("vehicles", "car", "Véhicules et routes|Vehicles and roads|Vehículos y carreteras|Veicoli e strade",
          "car automobile truck bus van suv jeep limousine sportscar convertible police_car motorcycle scooter motorhome semi_truck vehicle conveyance road road_other street driveway parking_lot traffic_light crosswalk road_safety_equipment car_seat license_plate dashboard tire wheel firetruck atv go_kart motorsport nascar formula_one_car grand_prix motocross"),
        f("aircraft", "airplane", "Avions et hélicoptères|Aircraft|Aviones y helicópteros|Aerei ed elicotteri", "aircraft airplane airport airshow helicopter hangar hangglider parachute parasailing skydiving drone_machine rocket propeller balloon_hotair"),
        f("trains", "tram.fill", "Trains|Trains|Trenes|Treni", "train train_real train_station tramway streetcar monorail track_rail railroad cableway chairlift"),
        f("boats", "ferry", "Bateaux|Boats|Barcos|Barche", "boat barge boathouse canoe cruise_ship harbour houseboat jetski kayak lifejacket lifesaver mast oar rafting rowboat sailboat shipyard speedboat submarine_water warship watercraft yacht dock pier"),
        f("sea", "beach.umbrella", "Mer et plage|Sea and beach|Mar y playa|Mare e spiaggia", "ocean beach shore sand sand_dune seashell sandcastle surfing surfboard bodyboard kiteboarding windsurfing sunbathing lighthouse seaweed coral_reef underwater scuba snorkeling"),
        f("water", "drop", "Eau et rivières|Water and rivers|Agua y ríos|Acqua e fiumi", "water water_body lake river creek waterfall fountain pool dam waterways wetland geyser swimming diving waterpolo watering_can sprinkler"),
        f("nature", "leaf", "Nature et végétation|Nature and plants|Naturaleza y plantas|Natura e piante",
          "forest tree foliage grass vegetation jungle plant decorative_plant trail hiking park garden evergreen oak_tree palm_tree sequoia willow eucalyptus_tree maple_tree ferns moss mangrove shrub flower blossom bouquet flower_arrangement rose tulip sunflower daisy orchid bonsai cactus ivy branch"),
        f("landscape", "mountain.2", "Paysages|Landscapes|Paisajes|Paesaggi", "mountain canyon cliff hill desert glacier iceberg rocks cave megalith land dirt_road island volcano"),
        f("sky", "cloud.sun", "Ciel et météo|Sky and weather|Cielo y clima|Cielo e meteo", "sky blue_sky cloudy rainbow lightning storm thunderstorm tornado blizzard haze sun moon celestial_body celestial_body_other sunset_sunrise aurora daytime"),
        f("night", "moon.stars", "Nuit|Night|Noche|Notte", "night_sky moon nightclub disco_ball lamppost lantern spotlight"),
        f("snow", "snowflake", "Neige et hiver|Snow and winter|Nieve e invierno|Neve e inverno", "snow blizzard ice iceberg glacier igloo skiing ski_equipment ski_boot sled sledding snowboard snowboarding snowman snowmobile snowshoe winter_sport frozen ice_skates ice_skating"),
        f("fire", "flame", "Feu et flammes|Fire and flames|Fuego y llamas|Fuoco e fiamme", "fire flame embers fireplace lava volcano lighter matches candle candlestick"),
        f("fireworks", "sparkles", "Feux d'artifice|Fireworks|Fuegos artificiales|Fuochi d'artificio", "fireworks firecracker pyrotechnics sparkler"),
        f("city", "building.2", "Ville et bâtiments|City and buildings|Ciudad y edificios|Città ed edifici", "cityscape skyscraper building street sidewalk alley apartment house_single bridge tower billboards storefront structure domicile roof chimney balcony porch patio deck fence garage"),
        f("monuments", "building.columns", "Châteaux et monuments|Castles and monuments|Castillos y monumentos|Castelli e monumenti", "castle ruins monument obelisk statue megalith pyramid belltower clock_tower dome arch gargoyle stained_glass grave"),
        f("shops", "cart", "Commerces et restaurants|Shops and restaurants|Tiendas y restaurantes|Negozi e ristoranti", "interior_shop storefront shopping_cart restaurant bar casino atm"),
        f("sport", "figure.run", "Sport|Sports|Deportes|Sport",
          "sport athletics ballgames baseball basketball billiards bowling boxing cheerleading cricket_sport cycling dartboard fencing_sport football golf golf_course gymnastics hockey martial_arts rugby soccer softball squash_sport tennis volleyball wrestling kickboxing sumo skateboarding skatepark rock_climbing workout yoga health_club treadmill dumbbell barbell badminton ping_pong racquet equestrian rodeo hurdle"),
        f("music", "music.mic", "Musique et scène|Music and stage|Música y escenario|Musica e palco", "musical_instrument string_instrument guitar piano violin drum cello flute clarinet saxophone trumpet trombone tuba harp accordion ukulele organ_instrument orchestra brass_music woodwind singer deejay karaoke microphone bongo_drum xylophone tambourine turntable"),
        f("shows", "theatermasks", "Spectacle et danse|Shows and dance|Espectáculos y baile|Spettacoli e danza", "dancing ballet ballet_dancer bellydance breakdancing hula samba dragon_parade theater performance entertainer circus clown juggling puppet acrobat"),
        f("party", "party.popper", "Fêtes et cérémonies|Parties and ceremonies|Fiestas y ceremonias|Feste e cerimonie", "celebration ceremony wedding wedding_cake wedding_dress bride groom bridesmaid birthday_cake gift gift_card balloon christmas_tree christmas_decoration easter_egg santa_claus jack_o_lantern poinsettia red_envelope"),
        f("dogs", "dog", "Chiens|Dogs|Perros|Cani",
          "dog canine australian_shepherd basenji basset beagle bernese_mountain bichon bulldog chihuahua collie corgi dachshund dalmatian doberman german_shepherd greyhound hound husky irish_wolfhound jack_russell_terrier malamute malinois mastiff newfoundland pitbull pomeranian poodle pug retriever ridgeback rottweiler saint_bernard schnauzer setter sheepdog spaniel terrier vizsla weimaraner leash"),
        f("cats", "cat", "Chats|Cats|Gatos|Gatti", "cat adult_cat feline kitten"),
        f("horses", "figure.equestrian.sports", "Chevaux|Horses|Caballos|Cavalli", "horse dressage jockey_horse saddle horseshoe donkey"),
        f("birds", "bird", "Oiseaux|Birds|Aves|Uccelli", "bird eagle owl parrot parakeet peacock pigeon dove cockatoo flamingo heron hummingbird gull ostrich pelican penguin puffin raven sandpiper sparrow stork swan toucan vulture woodpecker peregrine raptor birdhouse"),
        f("wild", "pawprint", "Animaux sauvages|Wild animals|Animales salvajes|Animali selvatici",
          "animal mammal lion tiger bear leopard cheetah cougar bobcat lynx coyote_wolf fox hyena elephant giraffe zebra rhinoceros hippopotamus kangaroo koala panda lemur camel deer elk moose bison boar marsupial rodent squirrel raccoon porcupine skunk otter seal sealion walrus ungulates hedgehog chinchilla gerbil hamster ferret rat llama rabbit"),
        f("marine", "fish", "Vie marine|Marine life|Vida marina|Vita marina",
          "fish aquarium fishbowl fishtank anchovy angelfish barracuda clownfish goldfish guppy koi lionfish mackerel puffer_fish salmon sardine seabass seahorse snapper stingray sunfish swordfish trout tuna whale cetacean dolphin shark cephalopod jellyfish crab lobster clam oyster mollusk starfish urchin barnacle conch scallop mussel shellfish"),
        f("critters", "ant", "Insectes et reptiles|Insects and reptiles|Insectos y reptiles|Insetti e rettili",
          "insect ant bee beehive beekeeping butterfly caterpillar centipede dragonfly ladybug millipede moth scarab spider spiderweb scorpion snail worm arthropods arachnid reptile snake lizard alligator_crocodile iguana gecko chameleon python rattlesnake tortoise turtle frog toad monitor_lizard dinosaur gastropod"),
        f("farm", "leaf.circle", "Campagne et ferme|Farm and countryside|Campo y granja|Campagna e fattoria", "farm barn agriculture cow sheep goat pig tractor orchard vineyard rice_field greenhouse scarecrow wheat straw_hay silo windmill watermill prairie_dog"),
        f("construction", "hammer", "Chantier et outils|Construction and tools|Obras y herramientas|Cantieri e attrezzi",
          "crane_construction bulldozer backhoe forklift hardhat tool toolbox power_saw wrench pliers hammer screwdriver machine gears wind_turbine solar_panel smokestack pulley winch mower axe rake broom bucket"),
        f("games", "puzzlepiece", "Jeux et jouets|Games and toys|Juegos y juguetes|Giochi e giocattoli", "doll stuffed_animals vehicle_toy train_toy figurine blocks puzzles jigsaw kite playground slide_toy seesaw swing_playground trampoline board_game chess play_card dice domino poker games"),
        f("art", "paintbrush", "Art et peinture|Art and paintings|Arte y pintura|Arte e pittura", "painting art easel illustrations graffiti origami rangoli henna tattoo paintbrush"),
        f("combat", "shield", "Armes et combat|Weapons and combat|Armas y combate|Armi e combattimento", "sword archery paintball hunting skull skeleton"),
    ]

    static let byID: [String: Family] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    /// étiquette Vision → indices des familles qui la contiennent
    static let ofLabel: [String: [Int]] = {
        var d: [String: [Int]] = [:]
        for (i, fam) in all.enumerated() { for l in fam.labels { if d[l]?.contains(i) != true { d[l, default: []].append(i) } } }
        return d
    }()
}

enum SoundFamilies {
    private static func f(_ id: String, _ symbol: String, _ names: String, _ labels: String) -> Family {
        Family(id: id, symbol: symbol, names: names.components(separatedBy: "|"), labels: labels.split(separator: " ").map(String.init))
    }
    /// Tous les instruments de musique : la famille « Musique » les regroupe avec l'étiquette générale.
    static let instruments = "accordion acoustic_guitar bagpipes banjo bass_drum bass_guitar bassoon bowed_string_instrument brass_instrument cello clarinet cowbell cymbal didgeridoo double_bass drum drum_kit electric_guitar electric_piano electronic_organ flute french_horn glockenspiel gong guitar guitar_strum guitar_tapping hammond_organ harmonica harp harpsichord hi_hat keyboard_musical mallet_percussion mandolin marimba_xylophone oboe orchestra organ percussion piano plucked_string_instrument saxophone shofar singing_bowl sitar snare_drum steel_guitar_slide_guitar steelpan synthesizer tabla tambourine theremin timpani trombone trumpet tuning_fork ukulele vibraphone violin_fiddle wind_instrument zither disc_scratching"

    static let all: [Family] = [
        f("speech", "text.bubble", "Parole|Speech|Habla|Parlato", "speech"),
        f("whisper", "ear", "Chuchotements|Whispers|Susurros|Sussurri", "whispering"),
        f("crowd", "person.3", "Foule et brouhaha|Crowd noise|Multitud y barullo|Folla e brusio", "crowd babble chatter booing"),
        f("shout", "exclamationmark.bubble", "Cris|Shouts|Gritos|Urla", "shout yell screaming battle_cry children_shouting"),
        f("laugh", "face.smiling", "Rires|Laughter|Risas|Risate", "laughter belly_laugh chuckle_chortle giggling snicker baby_laughter"),
        f("cry", "drop", "Pleurs|Crying|Llanto|Pianto", "crying_sobbing baby_crying"),
        f("applause", "hands.clap", "Applaudissements|Applause|Aplausos|Applausi", "applause clapping cheering"),
        f("singing", "music.mic", "Chant|Singing|Canto|Canto", "singing choir_singing yodeling humming rapping whistling"),
        f("music", "music.note", "Musique|Music|Música|Musica", "music " + instruments),
        f("burp", "wind", "Rots|Burps|Eructos|Rutti", "burp"),
        f("sneeze", "nose", "Éternuements et toux|Sneezes and coughs|Estornudos y tos|Starnuti e tosse", "sneeze cough nose_blowing hiccup"),
        f("breath", "lungs", "Respiration et soupirs|Breathing and sighs|Respiración y suspiros|Respiro e sospiri", "breathing sigh gasp snoring"),
        f("eating", "fork.knife", "Manger et boire|Eating and drinking|Comer y beber|Mangiare e bere", "chewing biting slurp gargling"),
        f("steps", "figure.walk", "Pas et déplacements|Footsteps|Pasos|Passi", "person_walking person_running person_shuffling"),
        f("door", "door.left.hand.closed", "Portes|Doors|Puertas|Porte", "door door_slam door_sliding door_bell knock drawer_open_close"),
        f("gunfire", "scope", "Coups de feu|Gunfire|Disparos|Colpi di arma da fuoco", "gunshot_gunfire artillery_fire"),
        f("explosion", "burst", "Explosions|Explosions|Explosiones|Esplosioni", "boom eruption"),
        f("fireworks", "sparkles", "Feux d'artifice et pétards|Fireworks and firecrackers|Fuegos artificiales y petardos|Fuochi d'artificio e petardi", "fireworks firecracker"),
        f("fire", "flame", "Feu|Fire|Fuego|Fuoco", "fire fire_crackle"),
        f("thunder", "cloud.bolt", "Tonnerre et orage|Thunder and storm|Trueno y tormenta|Tuono e temporale", "thunder thunderstorm"),
        f("rain", "cloud.rain", "Pluie|Rain|Lluvia|Pioggia", "rain raindrop"),
        f("wind", "wind", "Vent|Wind|Viento|Vento", "wind wind_noise_microphone wind_rustling_leaves"),
        f("water", "drop", "Eau|Water|Agua|Acqua", "water liquid_dripping liquid_filling_container liquid_pouring liquid_sloshing liquid_splashing liquid_spraying liquid_squishing liquid_trickle_dribble stream_burbling water_tap_faucet sink_filling_washing bathtub_filling_washing toilet_flush water_pump underwater_bubbling gurgling"),
        f("sea", "water.waves", "Mer et cascades|Sea and waterfalls|Mar y cascadas|Mare e cascate", "ocean sea_waves waterfall"),
        f("glass", "wineglass", "Verre brisé|Breaking glass|Cristal roto|Vetro rotto", "glass_breaking glass_clink"),
        f("impact", "burst.fill", "Chocs et claquements|Impacts and slaps|Golpes y palmadas|Colpi e schiaffi", "thump_thud slap_smack crushing bowling_impact hammer finger_snapping tap wood_cracking chopping_wood tearing crumpling_crinkling whoosh_swoosh_swish squeak rattle_instrument"),
        f("sirens", "light.beacon.max", "Sirènes|Sirens|Sirenas|Sirene", "siren ambulance_siren police_siren civil_defense_siren fire_engine_siren emergency_vehicle"),
        f("alarms", "bell", "Alarmes et sonneries|Alarms and bells|Alarmas y timbres|Allarmi e campanelli", "alarm_clock smoke_detector beep reverse_beeps telephone telephone_bell_ringing ringtone bell church_bell chime wind_chime bicycle_bell air_horn"),
        f("cars", "car", "Voitures et circulation|Cars and traffic|Coches y tráfico|Auto e traffico", "car_passing_by car_horn vehicle_skidding race_car engine engine_accelerating_revving engine_idling engine_knocking engine_starting traffic_noise truck bus motorcycle power_windows"),
        f("aircraft", "airplane", "Avions et hélicoptères|Aircraft|Aviones y helicópteros|Aerei ed elicotteri", "aircraft airplane helicopter"),
        f("trains", "tram.fill", "Trains|Trains|Trenes|Treni", "train train_horn train_wheels_squealing train_whistle rail_transport railroad_car subway_metro"),
        f("boats", "ferry", "Bateaux|Boats|Barcos|Barche", "boat_water_vehicle motorboat_speedboat rowboat_canoe_kayak sailing foghorn"),
        f("dogs", "dog", "Chiens|Dogs|Perros|Cani", "dog dog_bark dog_bow_wow dog_growl dog_howl dog_whimper coyote_howl"),
        f("cats", "cat", "Chats|Cats|Gatos|Gatti", "cat cat_meow cat_purr"),
        f("birds", "bird", "Oiseaux|Birds|Aves|Uccelli", "bird bird_chirp_tweet bird_flapping bird_squawk bird_vocalization crow_caw chicken chicken_cluck rooster_crow duck_quack goose_honk owl_hoot pigeon_dove_coo turkey_gobble fowl"),
        f("animals", "pawprint", "Autres animaux|Other animals|Otros animales|Altri animali", "cow_moo horse_clip_clop horse_neigh pig_oink sheep_bleat lion_roar whale_vocalization frog frog_croak insect bee_buzz fly_buzz mosquito_buzz cricket_chirp snake_hiss snake_rattle elk_bugle"),
        f("tools", "hammer", "Outils et machines|Tools and machines|Herramientas y máquinas|Attrezzi e macchine", "drill chainsaw saw power_tool hedge_trimmer lawn_mower sewing_machine printer vacuum_cleaner blender hair_dryer microwave_oven electric_shaver mechanical_fan air_conditioner ratchet_and_pawl toothbrush"),
        f("kitchen", "fork.knife.circle", "Cuisine et vaisselle|Kitchen sounds|Cocina y vajilla|Cucina e stoviglie", "dishes_pots_pans cutlery_silverware frying_food chopping_food boiling"),
        f("typing", "keyboard", "Clavier et écriture|Typing and writing|Teclado y escritura|Tastiera e scrittura", "typing typing_computer_keyboard typewriter writing click keys_jangling scissors zipper coin_dropping camera"),
        f("sports", "figure.run", "Sport|Sports|Deportes|Sport", "basketball_bounce playing_badminton playing_hockey playing_squash playing_table_tennis playing_tennis playing_volleyball rope_skipping skateboard skiing bicycle scuba_diving"),
        f("clock", "clock", "Horloges|Clocks|Relojes|Orologi", "clock tick tick_tock"),
        f("silence", "speaker.slash", "Silence|Silence|Silencio|Silenzio", "silence"),
    ]

    static let byID: [String: Family] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    static let ofLabel: [String: [Int]] = {
        var d: [String: [Int]] = [:]
        for (i, fam) in all.enumerated() { for l in fam.labels { if d[l]?.contains(i) != true { d[l, default: []].append(i) } } }
        return d
    }()
}

extension L {
    /// Noms des familles : intégrés à la table des textes pour que `--check-l10n` vérifie les quatre langues.
    static let partFamilies: [String: [String]] = {
        var d: [String: [String]] = [:]
        for f in SceneFamilies.all { d["scene." + f.id] = f.names }
        for f in SoundFamilies.all { d["sound." + f.id] = f.names }
        return d
    }()
}
