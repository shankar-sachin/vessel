import Foundation

/// The vocabulary the generator builds sentences from.
///
/// Every list here is a decision about what the model will and won't understand,
/// so they're written out rather than scraped: a phrasing that isn't in this
/// file is a phrasing the parser will be weak at, and that should be visible
/// and fixable in one place.
enum Grammar {

    // MARK: - Intents

    enum Intent: String, CaseIterable {
        case logFood, logWater, logSymptom, journalEntry, query, correction
    }

    // MARK: - Token labels
    //
    // Flat per-token labels rather than BIO. `MLWordTagger` handles flat labels
    // natively, and food names are contiguous spans in practice, so the extra
    // B-/I- distinction would double the label space for almost no gain.

    enum Label: String {
        case none = "NONE"
        case quantity = "QTY"
        case unit = "UNIT"
        case food = "FOOD"
        case prep = "PREP"
        case brand = "BRAND"
        case time = "TIME"
        case meal = "MEAL"
        case negation = "NEG"
        case symptom = "SYMPTOM"
        case severity = "SEVERITY"
        case drink = "DRINK"
    }

    // MARK: - Fillers and frames

    static let leadIns = [
        "", "", "", "", "",              // most utterances have none
        "i had", "i ate", "i just had", "i just ate", "had",
        "log", "add", "record", "i'm having", "just had", "having"
    ]

    static let tailOffs = ["", "", "", "", "", "", "please", "thanks", "to my log"]

    // MARK: - Quantities

    static let quantityForms: [String] = [
        "1", "2", "3", "4", "5", "6", "8", "10", "12",
        "one", "two", "three", "four", "six",
        "half", "a half", "1/2", "1/4", "3/4", "½", "¼",
        // Spoken fractions. People dictating say "a quarter of a melon"; the
        // corpus only ever wrote it "1/4", so the word itself was unseen.
        "quarter", "a quarter", "third", "a third", "two thirds", "three quarters",
        "1.5", "2.5", "1 1/2", "two and a half", "one and a half",
        "a couple of", "a few", "some", "2-3", "3 to 4"
    ]

    static let articles = ["a", "an", "the"]

    /// Spoken numbers as the normalizer will have rewritten them.
    ///
    /// The parser converts number words to digits *before* the tagger runs, so
    /// a corpus written only in words trains on text the tagger never sees.
    /// "A quarter of a melon" reaches it as "a 0.25 of a melon", a shape the
    /// model had no example of, and it swallowed the whole span as the food
    /// name. Generating both surfaces closes the gap.
    static let spokenNumerals: [String: String] = [
        "half": "0.5", "quarter": "0.25", "third": "0.33",
        "two thirds": "0.67", "three quarters": "0.75",
        "one": "1", "two": "2", "three": "3", "four": "4",
        "five": "5", "six": "6", "eight": "8", "ten": "10", "twelve": "12"
    ]

    /// Words that sit between a number and what it counts.
    static let quantityFillers = ["more", "extra", "another", "further", "other"]

    /// Partitive phrases — "a wedge of", "the rest of", "seconds of".
    ///
    /// These exist because `buildWater` used to be the only thing in the whole
    /// corpus that produced the shape `<something> of <something>`. Every
    /// partitive in the language therefore looked like a drink, and "a quarter
    /// of a melon", "a wedge of brie" and "seconds of the lasagne" were all
    /// logged as water. The construction is common and carries no drink
    /// meaning whatsoever, so food has to own it too.
    static let foodPortions = [
        "a quarter", "a third", "half", "the other half", "a wedge", "a slice",
        "a piece", "a bit", "a portion", "a small portion", "a big portion",
        "the rest", "the last", "seconds", "a chunk", "a spoonful", "a mouthful",
        "a couple of bites", "most", "a small bowl", "a big plate", "a good chunk"
    ]

    /// How people say they ate, when they don't say "had".
    ///
    /// Each is checked against ordinary usage before being added — the same
    /// discipline as the symptom idioms below. "Smashed" and "demolished" carry
    /// no other meaning in a food diary; something like "finished" would, and
    /// is left to the plain lead-ins.
    static let eatingVerbs = [
        "smashed", "demolished", "polished off", "picked at", "grabbed",
        "wolfed down", "tucked into", "snacked on", "nibbled on", "went back for",
        "had seconds of", "made myself", "threw together", "got myself"
    ]

    /// Dishes people name in ways USDA never does.
    ///
    /// The food database is the source of food *names*, but it is a nutrition
    /// reference: it has no row called "fry up" or "meal deal", and nobody
    /// dictating their breakfast says "Egg, whole, cooked, fried". These are
    /// training phrasings, not a food list — the resolver still has to match
    /// them against the real database at parse time.
    static let colloquialDishes = [
        "fry up", "full english", "cheese toastie", "toastie", "sausage roll",
        "bacon sandwich", "jacket potato", "shepherds pie", "cottage pie",
        "takeaway", "leftovers", "ready meal", "meal deal", "stir fry",
        "roast dinner", "sunday roast", "protein shake", "protein bar",
        "smoothie bowl", "burrito", "tikka masala", "pad thai",
        "ploughmans", "buddha bowl", "overnight oats", "eggs benedict",
        // No dish here may contain "and", "with" or "on" — see FoodLoader.
        "carbonara", "katsu curry", "chilli con carne", "moussaka"
    ]

    /// Where and when eating happened, as a trailing clause that means nothing.
    ///
    /// Added because the tagger was labelling them FOOD — "some grapes while
    /// cooking" extracted "while cooking" and dropped the grapes. Anything that
    /// habitually trails a food phrase has to appear in the corpus labelled
    /// NONE, or the tagger will find something to do with it.
    static let trailingClauses = [
        "while cooking", "on the way home", "on the way out", "at my desk",
        "in front of the tv", "before the gym", "after training",
        "after my workout", "on the train", "at work", "between meetings",
        "while watching a film", "standing up", "in the car", "at my mums"
    ]

    // MARK: - Units

    static let massUnits = ["g", "grams", "gram", "oz", "ounces", "ounce", "lb", "pounds"]
    static let volumeUnits = ["ml", "milliliters", "l", "liters", "cup", "cups",
                              "tbsp", "tablespoon", "tablespoons",
                              "tsp", "teaspoon", "teaspoons", "fl oz", "fluid ounces"]
    static let countUnits = ["slice", "slices", "piece", "pieces", "serving", "servings",
                             "bowl", "bowls", "plate", "plates", "handful", "handfuls",
                             "glass", "glasses", "bottle", "bottles", "can", "cans",
                             "mug", "mugs", "scoop", "scoops", "bar", "bars",
                             // Packaging. People buy food in these and say so.
                             "pack", "packet", "packets", "box", "boxes", "bag", "bags",
                             "tub", "tubs", "punnet", "tin", "tins", "jar", "jars",
                             "carton", "cartons", "sachet", "tray", "block", "wrap"]

    static var allUnits: [String] { massUnits + volumeUnits + countUnits }

    // MARK: - Preparation

    static let preps = [
        "grilled", "fried", "baked", "boiled", "steamed", "roasted", "raw",
        "scrambled", "poached", "toasted", "cooked", "fresh", "frozen",
        "homemade", "leftover", "plain", "chopped", "sliced"
    ]

    static let brands = [
        "starbucks", "mcdonalds", "subway", "chipotle", "pret", "greggs",
        "tesco", "sainsburys", "trader joes", "whole foods", "kelloggs",
        "quaker", "heinz", "nestle", "danone"
    ]

    // MARK: - Time

    static let timePhrases = [
        "this morning", "this afternoon", "this evening", "tonight",
        "last night", "yesterday", "yesterday morning", "yesterday evening",
        "at 8am", "at 9am", "at noon", "at 1pm", "at 6pm", "at 7:30pm",
        "around 3pm", "earlier", "just now", "a bit ago"
    ]

    static let mealPhrases = [
        "for breakfast", "for lunch", "for dinner", "for supper",
        "at breakfast", "at lunch", "at dinner", "as a snack", "for brunch",
        // "with lunch" appeared nowhere in the corpus, in any intent. A drink
        // named beside a meal — "sparkling water with lunch", "a beer with
        // dinner" — therefore looked exactly like food with an accompanying
        // drink, and five separate drink logs were being filed as meals.
        "with breakfast", "with lunch", "with dinner", "with supper",
        "with my meal", "with a meal", "after dinner", "after lunch",
        "before dinner", "with my breakfast"
    ]

    // MARK: - Water and drinks

    static let drinkNouns = [
        "water", "coffee", "tea", "juice", "orange juice", "milk", "soda",
        "sparkling water", "green tea", "black coffee", "latte", "smoothie",
        "lemonade", "herbal tea", "iced tea", "apple juice",
        // Named coffees and soft drinks are ordered by name, with no vessel
        // and often no quantity — "large flat white" is a complete utterance.
        "flat white", "americano", "cappuccino", "espresso", "cortado", "mocha",
        "hot chocolate", "diet coke", "coke", "cola", "squash", "cordial",
        "kombucha", "milkshake", "still water", "tap water", "fizzy water",
        "brew", "cuppa", "peppermint tea", "chamomile tea", "energy drink",
        // Alcohol is hydration the Date Log wants flagged, not a food.
        "beer", "wine", "red wine", "white wine", "pint", "cider", "prosecco",
        "gin and tonic", "glass of wine", "whisky", "vodka soda",
        // And the ways coffee gets ordered.
        "decaf", "decaf coffee", "filter coffee", "iced coffee", "oat latte"
    ]

    /// Size and style words that attach directly to a drink.
    ///
    /// Without them "large flat white" has no drink-shaped structure at all —
    /// no vessel, no "of", no quantity — and the classifier read it as food.
    static let drinkModifiers = [
        "large", "small", "regular", "tall", "grande", "double", "single",
        "iced", "hot", "strong", "weak", "quick", "cheeky", "another"
    ]

    static let drinkVessels = ["glass", "glasses", "cup", "cups", "bottle", "bottles",
                               "mug", "mugs", "can", "cans", "sip", "sips"]

    // MARK: - Symptoms

    static let symptomPhrases: [(text: String, tokens: [String])] = [
        ("bloated", ["bloated"]), ("bloating", ["bloating"]),
        ("gassy", ["gassy"]), ("gas", ["gas"]),
        ("nauseous", ["nauseous"]), ("nausea", ["nausea"]),
        ("heartburn", ["heartburn"]), ("reflux", ["reflux"]),
        ("cramps", ["cramps"]), ("stomach ache", ["stomach", "ache"]),
        ("stomach pain", ["stomach", "pain"]),
        ("headache", ["headache"]), ("a migraine", ["migraine"]),
        ("tired", ["tired"]), ("fatigue", ["fatigue"]),
        ("brain fog", ["brain", "fog"]), ("foggy", ["foggy"]),
        ("itchy", ["itchy"]), ("a rash", ["rash"]),
        ("congested", ["congested"]), ("diarrhea", ["diarrhea"]),
        ("constipated", ["constipated"]), ("indigestion", ["indigestion"]),
        // Idiom. People rarely name a symptom clinically — they describe it.
        ("stomach is killing me", ["stomach", "is", "killing", "me"]),
        ("stomach killing me", ["stomach", "killing", "me"]),
        ("not feeling great", ["not", "feeling", "great"]),
        ("feel rough", ["feel", "rough"]),
        ("stomach is upset", ["stomach", "is", "upset"]),
        ("upset stomach", ["upset", "stomach"]),
        ("queasy", ["queasy"]), ("sluggish", ["sluggish"]),
        ("head is pounding", ["head", "is", "pounding"]),
        // Deliberately omitted: "run down", "wiped out", "feeling off".
        // Each shares its head word with something common and unrelated — a
        // corpus containing "run down" taught the classifier that "run"
        // signals a symptom, which then read "bottle of water after my run"
        // as one. An idiom is only worth generating if its words don't
        // collide with ordinary usage.
        ("belly ache", ["belly", "ache"]), ("tummy ache", ["tummy", "ache"]),
        // Idioms that pass the collision test above: none of these words does
        // any other work in a food diary. "Flared up" and "playing up" are how
        // people actually describe a recurring complaint, and both were being
        // filed as journal entries because the corpus only ever named symptoms
        // clinically.
        ("flared up", ["flared", "up"]), ("flaring up", ["flaring", "up"]),
        ("playing up", ["playing", "up"]), ("acting up", ["acting", "up"]),
        ("puffy", ["puffy"]), ("bloaty", ["bloaty"]),
        ("cramping up", ["cramping", "up"]), ("cramping", ["cramping"]),
        ("churning", ["churning"]), ("gurgling", ["gurgling"]),
        ("bunged up", ["bunged", "up"]), ("blocked up", ["blocked", "up"]),
        ("sick", ["sick"]), ("unsettled", ["unsettled"]),
        ("sore", ["sore"]), ("swollen", ["swollen"]), ("itching", ["itching"]),
        ("windy", ["windy"]), ("banging", ["banging"]), ("burping", ["burping"]),
        ("lightheaded", ["lightheaded"]), ("dizzy", ["dizzy"]),
        ("sore throat", ["sore", "throat"]), ("aching", ["aching"]), ("ache", ["ache"])
    ]

    /// Complaints that are only unambiguous once something is complaining.
    ///
    /// "Off" is the clearest case: on its own it is "polished off the lasagne"
    /// and "off the plate", and generating it as a bare symptom would repeat
    /// the "run down" mistake exactly. Attached to a body part — "my gut has
    /// been off" — it can only mean one thing, so these are generated *only*
    /// in the subject frame and never alone.
    static let subjectSymptoms: [(text: String, tokens: [String])] = [
        ("off", ["off"]), ("not right", ["not", "right"]),
        ("in bits", ["in", "bits"]), ("all over the place", ["all", "over", "the", "place"]),
        ("a mess", ["a", "mess"]), ("rough", ["rough"]), ("tender", ["tender"])
    ]

    /// What is doing the complaining.
    ///
    /// "Flared up" on its own is ambiguous; "my eczema has flared up" is not.
    /// The corpus had no way to say which part of you the symptom belongs to,
    /// which is most of why the idioms above read as prose.
    static let symptomSubjects = [
        "my stomach", "my gut", "my guts", "my belly", "my tummy",
        "my skin", "my eczema", "my head", "my joints", "my sinuses",
        "stomach", "skin", "gut", "my chest", "my throat",
        "head", "belly", "guts", "my eyes", "my nose", "my hands"
    ]

    /// Verbs linking a subject to its complaint — "my stomach *has been*".
    static let symptomLinkers = [
        "is", "has been", "'s been", "has", "was", "keeps", "is still", "'s"
    ]

    /// Offhand remarks people tack onto a food log.
    ///
    /// Without these the classifier reads any evaluative tail as a journal
    /// entry — "slice of cheesecake, was very good" was misfiled exactly so.
    static let foodAsides = [
        "", "", "", "", "", "", "", "",
        "was very good", "was really good", "was delicious", "pretty tasty",
        "was too much", "bit heavy", "not great", "really filling",
        "was lovely", "quite salty", "a bit dry"
    ]

    /// Drinks mentioned alongside food rather than logged on their own.
    ///
    /// "couple of biscuits with my tea" is a food log that happens to name a
    /// drink; generating these stops the classifier reading every mention of
    /// tea as a water log.
    /// Words joining one food to another.
    ///
    /// Every "with" in the corpus used to introduce a drink — "with my tea",
    /// "with a coffee" — so "half a baguette with butter" tagged *butter* as a
    /// drink and dragged the baguette in with it. "With" joins foods far more
    /// often than it introduces a drink, and the corpus said the opposite.
    static let foodConnectors = ["with", "and", "plus", "on", "topped with",
                                 "alongside", "and some", "with some", "and a bit of"]

    static let accompanyingDrinks = [
        "with my tea", "with my coffee", "with a coffee", "with some water",
        "and a coffee", "with tea", "alongside a coffee"
    ]

    static let symptomLeadIns = [
        "feeling", "i feel", "i'm feeling", "im feeling", "felt", "i felt",
        "got", "i've got", "ive got", "having", "experiencing", ""
    ]

    static let severityWords = [
        "mild", "mildly", "slight", "slightly", "a bit", "a little",
        "quite", "very", "really", "extremely", "severe", "severely", "bad", "terrible"
    ]

    // MARK: - Negation

    static let negations = ["no", "without", "not", "skip the", "hold the"]

    // MARK: - Journal

    static let journalOpeners = [
        "felt good today", "rough day", "slept badly", "energy was low",
        "feeling better than yesterday", "good day overall", "stressful day at work",
        "went for a long walk", "didn't sleep well", "woke up early",
        "productive morning", "quiet evening", "felt anxious this afternoon",
        "really tired all day", "had a good workout", "mood was steady"
    ]

    /// Days where nothing happened, which people still log.
    ///
    /// Every journal opener above describes an event. A day that contained no
    /// event is still a journal entry, and "nothing much to report" was being
    /// read as a *question* for want of anywhere better to put it.
    static let journalNonEvents = [
        "nothing much to report", "not much happened today", "same as usual",
        "same as always", "uneventful day", "quiet one today", "nothing eventful",
        "pretty standard day", "not much to say", "an ordinary day",
        "nothing worth noting", "much the same as yesterday"
    ]

    /// Intentions, which read as corrections without training.
    /// A day summed up in a couple of words, and what was in it.
    ///
    /// "busy one, barely sat down" and "caught up with an old friend" were both
    /// read as food logs — the corpus's journal entries all opened with a
    /// feeling or a sleep report, so a day described any other way had nothing
    /// to match against.
    static let journalDayDescriptors = [
        "busy one", "long one", "slow day", "hectic day", "easy day",
        "barely sat down", "on my feet all day", "back to back meetings",
        "nothing in the diary", "worked late again", "day off"
    ]

    static let journalSocial = [
        "caught up with an old friend", "saw the family", "had people over",
        "spoke to mum", "dinner with friends", "went round to theirs",
        "met up for a coffee", "quiet night in"
    ]

    static let journalIntentions = [
        "trying to eat earlier", "going to be more consistent",
        "want to be better about logging", "hoping to sleep more",
        "trying to cut back a bit", "going to cook more this week",
        "need to drink more water", "trying to be more consistent"
    ]

    /// Something done, and how it felt afterwards.
    ///
    /// The feeling half is why these matter: "went for a swim and felt great
    /// after" was classified as a symptom, because "felt" only ever introduced
    /// one. A good feeling after exercise is a journal entry.
    static let journalActivities = [
        "went for a swim", "went for a walk", "did some yoga", "went to the gym",
        "cycled to work", "played football", "went for a long run",
        "did a class after work", "got out for some air"
    ]

    static let journalActivityTails = [
        "and felt great after", "and felt good afterwards", "felt better for it",
        "and slept better", "and it helped", "really needed it",
        "and felt much clearer"
    ]

    static let journalContinuations = [
        "", "", "",
        "and i think it's the food", "probably need more sleep",
        "going to try eating earlier", "noticed it after lunch",
        "feeling more like myself", "hoping tomorrow is better"
    ]

    // MARK: - Queries

    static let queryTemplates = [
        "how many calories have i had", "how many calories today",
        "what did i eat yesterday", "what did i have for lunch",
        "how much water have i drunk", "how much water today",
        "what's my streak", "how long is my streak",
        "how much protein today", "what did i eat this morning",
        "show me yesterday", "did i log dinner", "am i over my calories",
        "how many meals today", "what triggered my bloating"
    ]

    // Queries used to be the fifteen fixed strings above, so any question that
    // named a food or a symptom — "is dairy a trigger for me", "what usually
    // upsets my stomach" — had only the food and symptom intents to match
    // against. These build questions out of parts instead.

    static let queryAmountStems = ["how much", "how many", "whats my", "what is my", "total"]
    static let queryMetrics = [
        "calories", "protein", "carbs", "sugar", "fat", "fibre", "fiber", "salt",
        "water", "glasses of water", "coffees", "caffeine"
    ]
    static let queryRanges = [
        "", "today", "so far", "so far today", "yesterday", "this week", "last week",
        "on monday", "on the weekend", "this month", "did i have", "have i had"
    ]
    static let queryRecallStems = [
        "what did i eat", "what did i have", "what did i drink", "show me what i ate",
        "what was my", "when did i last have", "when did i last eat", "list what i ate"
    ]
    static let queryCheckStems = [
        "did i hit my", "am i on track for my", "did i reach my", "how close am i to my",
        "am i under my", "am i over my"
    ]
    static let queryGoals = ["water goal", "protein goal", "calorie goal", "calories", "goal", "target"]

    /// Questions about what a food does to you — the Date Log's reason to exist.
    static let queryTriggerFrames: [(before: String, after: String)] = [
        ("is", "a trigger for me"), ("is", "a trigger"), ("does", "upset my stomach"),
        ("does", "agree with me"), ("does", "make me bloated"), ("is", "bad for me"),
        ("could", "be causing it"), ("am i reacting to", ""), ("how does", "affect me"),
        ("should i avoid", ""), ("is it the", "")
    ]
    static let querySymptomFrames = [
        "what usually upsets my stomach", "what makes me bloated", "what are my triggers",
        "why do i get heartburn", "what causes my cramps", "what foods make me gassy",
        "any patterns with my bloating", "what is giving me headaches",
        "what could be causing this", "whats upsetting my gut", "what sets off my reflux",
        "why am i always bloated", "what should i avoid"
    ]

    /// Heads that name a category or a container rather than a food. Drinks
    /// and units are excluded separately, from their own lists.
    static let nonFoodHeads: Set<String> = [
        "food", "foods", "mix", "substitute", "topping", "bowl", "leaves", "product",
        "products", "formula", "babyfood", "beverage", "beverages", "drink", "drinks",
        "restaurant", "supplement", "powder", "base", "meal", "dinner", "lunch", "breakfast"
    ]

    /// Pourables and spreads, which join a food as a *food*: "granola with
    /// milk", "pancakes with syrup". Milk otherwise only ever appeared as a
    /// drink, so "granola with milk" came back as a drink named "granola with
    /// milk".
    static let condiments = [
        "milk", "yoghurt", "yogurt", "cream", "custard", "honey", "syrup", "maple syrup",
        "butter", "jam", "peanut butter", "cream cheese", "hummus", "mayo", "ketchup",
        "gravy", "cheese", "salsa", "guacamole", "sour cream", "olive oil", "pesto"
    ]

    /// Moods, which follow "feeling" exactly as symptoms do.
    ///
    /// "feeling motivated this week" was read as a symptom: every "feeling" in
    /// the corpus introduced one.
    static let journalMoods = [
        "motivated", "positive", "calm", "stressed", "happy", "content", "grateful",
        "productive", "lazy", "hopeful", "overwhelmed", "rested", "focused", "restless",
        "upbeat", "unsettled", "proud of myself", "more like myself", "a bit down",
        "fed up", "optimistic", "on top of things"
    ]
    static let journalMoodLeadIns = ["feeling", "felt", "i feel", "been feeling", "im feeling", "mostly feeling"]
    static let journalMoodTails = ["", "", "this week", "today", "lately", "about work", "for once", "overall"]

    /// "had a good chat with my sister" — "had" not introducing food.
    static let journalHadEvents = ["chat", "catch up", "call", "talk", "walk", "laugh", "day out", "row", "meeting", "long talk"]
    static let journalHadAdjectives = ["", "good", "long", "lovely", "quick", "proper", "nice", "tough", "great"]
    static let journalCompanions = [
        "with my sister", "with my brother", "with mum", "with dad", "with a friend",
        "with the team", "with my partner", "with an old friend", "with my boss", "with the kids"
    ]

    /// Tails tying a symptom to something eaten without naming it.
    static let symptomVagueTails = [
        "after that meal", "after that", "after eating", "since eating", "after i ate",
        "all day", "all evening", "since this morning", "again"
    ]

    // MARK: - Corrections

    static let correctionOpeners = [
        "no i meant", "actually it was", "change that to", "make that",
        "i meant", "sorry i meant", "that should be", "correction"
    ]
}
