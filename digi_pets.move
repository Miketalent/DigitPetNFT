/* 
    Relive the 90's with a blockchain twist by implementing your own, on-chain digital pets!

    Key Concepts: 
        - Token v2 non-fungible tokens
        - Token v2 fungible tokens
        - Aptos coin
        - String utilities
*/
module overmind::digi_pets {

    //==============================================================================================
    // Dependencies
    //==============================================================================================
    use std::bcs;
    use std::vector;
    use std::object;
    use std::signer;
    use std::string_utils;
    use aptos_framework::coin;
    use aptos_framework::option;
    use aptos_framework::timestamp;
    use aptos_token_objects::token;
    use std::string::{Self, String};
    use aptos_token_objects::collection;
    use aptos_token_objects::property_map;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::aptos_coin::{AptosCoin};
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::account::{Self, SignerCapability};

    #[test_only]
    use aptos_token_objects::royalty;
    #[test_only]
    use aptos_framework::aptos_coin::{Self};

    //==============================================================================================
    // Constants - DO NOT MODIFY
    //==============================================================================================

    // Seed for resource account creation
    const SEED: vector<u8> = b"digi-pets";

    // constant for math
    const DAY_IN_SECONDS: u64 = 86400;

    // Types of digi pets
    const PET_TYPES: vector<vector<u8>> = vector<vector<u8>>[
        b"Dog", 
        b"Cat", 
        b"Snake", 
        b"Monkey"
    ];
    
    // Pet toys
    const TOY_FOR_DOG: vector<u8> = b"Chew toy";
    const TOY_FOR_CAT: vector<u8> = b"Yarn ball";
    const TOY_FOR_SNAKE: vector<u8> = b"Teddy bear";
    const TOY_FOR_MONKEY: vector<u8> = b"Beach ball";

    // Digi-pet collection information
    const DIGI_PET_COLLECTION_NAME: vector<u8> = b"Digi-Pets collection name";
    const DIGI_PET_COLLECTION_DESCRIPTION: vector<u8> = b"Digi-Pets collection description";
    const DIGI_PET_COLLECTION_URI: vector<u8> = b"Digi-Pets collection uri";

    // Digi-pet token information
    const DIGI_PET_TOKEN_DESCRIPTION: vector<u8> = b"Digi-Pets token description";
    const DIGI_PET_TOKEN_URI: vector<u8> = b"Digi-Pets token uri";

    // Digi-pet accessory collection information
    const DIGI_PET_ACCESSORY_COLLECTION_NAME: vector<u8> = b"Digi-Pets accessory collection name";
    const DIGI_PET_ACCESSORY_COLLECTION_DESCRIPTION: vector<u8> = b"Digi-Pets accessory collection description";
    const DIGI_PET_ACCESSORY_COLLECTION_URI: vector<u8> = b"Digi-Pets accessory collection uri";

    // property names for digi-pet token properties
    const PROPERTY_KEY_PET_NAME: vector<u8> = b"pet_name";
    const PROPERTY_KEY_PET_TYPE: vector<u8> = b"pet_type";
    const PROPERTY_KEY_PET_HEALTH: vector<u8> = b"pet_health";
    const PROPERTY_KEY_PET_HAPPINESS: vector<u8> = b"pet_happiness";
    const PROPERTY_KEY_PET_BIRTHDAY_TIMESTAMP_SECONDS: vector<u8> = b"pet_birthday";
    const PROPERTY_KEY_LAST_TIMESTAMP_FED: vector<u8> = b"last_timestamp_fed";
    const PROPERTY_KEY_LAST_TIMESTAMP_PLAYED_WITH: vector<u8> = b"last_timestamp_played_with";
    const PROPERTY_KEY_LAST_TIMESTAMP_UPDATED: vector<u8> = b"last_timestamp_updated";

    // Starting values for digi-pet token properties
    const STARTING_VALUE_PET_HEALTH: u64 = 100;
    const STARTING_VALUE_PET_HAPPINESS: u64 = 100;

    // Digi-pet food token information
    const FOOD_TOKEN_NAME: vector<u8> = b"food token name";
    const FOOD_TOKEN_DESCRIPTION: vector<u8> = b"food token description";
    const FOOD_TOKEN_URI: vector<u8> = b"food token uri";
    const FOOD_TOKEN_FUNGIBLE_ASSET_NAME: vector<u8> = b"food token fungible asset name";
    const FOOD_TOKEN_FUNGIBLE_ASSET_SYMBOL: vector<u8> = b"FOOD";
    const FOOD_TOKEN_ICON_URI: vector<u8> = b"food token icon uri";
    const FOOD_TOKEN_PROJECT_URI: vector<u8> = b"food token project uri";
    const FOOD_TOKEN_DECIMALS: u8 = 0;

    // Prices 
    const FOOD_TOKEN_PRICE: u64 = 5000000; // .05 APT
    const TOY_PRICE_APT: u64 = 100000000; // 1 APT

    // Starting value for toy
    const STARTING_TOY_DURABILITY: u64 = 50;

    //==============================================================================================
    // Error codes - DO NOT MODIFY
    //==============================================================================================

    const EInsufficientAptBalance: u64 = 0;
    const EInsufficientFoodBalance: u64 = 1;
    const ENotOwnerOfPet: u64 = 3;
    const EInvalidPetType: u64 = 4;

    //==============================================================================================
    // Module Structs - DO NOT MODIFY
    //==============================================================================================

    /* 
        Digi-pet NFT token type
    */
    struct DigiPetToken has key {
        // Used for editing the token data
        mutator_ref: token::MutatorRef,
        // Used for burning the token
        burn_ref: token::BurnRef,
        // USed for editing the token's property_map
        property_mutator_ref: property_map::MutatorRef, 
        // A list of toys for the digi-pet
        toys: vector<Toy>
    }

    /* 
        Information about a toy. Used for keeping the digi-pets happy
    */
    struct Toy has store, drop, copy {
        // name of the specific toy
        name: String,
        // how much happiness the toy can supply to the pet
        durability: u64
    }

    /* 
        struct for any fungible token for digi-pets
    */
    struct AccessoryToken has key {
        mutator_ref: property_map::MutatorRef,
        mint_ref: fungible_asset::MintRef,
        burn_ref: fungible_asset::BurnRef,
    }

    /* 
        Information to be used in the module
    */
    struct State has key {
        // signer cap of the module's resource account
        signer_cap: SignerCapability,
        // the number of pets adopted - used for pet name generation
        pet_count: u64, 
        // Events
        adopt_pet_events: EventHandle<AdoptPetEvent>, 
        feed_pet_events: EventHandle<FeedPetEvent>,
        play_with_pet_events: EventHandle<PlayWithPetEvent>,
        bury_pet_events: EventHandle<BuryPetEvent>,
    }

    //==============================================================================================
    // Event structs - DO NOT MODIFY
    //==============================================================================================

    /* 
        Event to be emitted when a pet is adopted
    */
    struct AdoptPetEvent has store, drop {
        // address of the account adopting the new pet
        adopter: address, 
        // name of the new pet
        pet_name: String, 
        // address of the pet
        pet: address,
        // type of pet
        pet_type: String
    }

    /* 
        Event to be emitted when a pet is fed
    */
    struct FeedPetEvent has store, drop {
        // address of the account that owns the pet
        owner: address, 
        // address of the pet
        pet: address
    }

    /* 
        Event to be emitted when a pet is played with
    */
    struct PlayWithPetEvent has store, drop {
        // address of the account that owns the pet
        owner: address, 
        // address of the pet
        pet: address
    }

    /* 
        Event to be emitted when a pet is buried
    */
    struct BuryPetEvent has store, drop {
        // address of the account that owns the pet
        owner: address, 
        // address of the pet
        pet: address
    }

    //==============================================================================================
    // Functions
    //==============================================================================================

    /* 
        Initializes the module by creating a resource account, registering with AptosCoin, creating
        the token collectiions, and setting up the State resource.
        @param account - signer representing the module publisher
    */
    fun init_module(account: &signer) {
        // TODO: Create a resource account with the account signer and the `SEED` constant
        let (resource_account, resource_signer_cap) = account::create_resource_account(account, SEED);
        // TODO: Register the resource account with AptosCoin
        coin::register<AptosCoin>(&resource_account);
        // TODO: Create an NFT collection with an unlimied supply and the following aspects: 
        //          - name: DIGI_PET_COLLECTION_NAME
        //          - description: DIGI_PET_COLLECTION_DESCRIPTION
        //          - uri: DIGI_PET_COLLECTION_URI
        //          - royalty: no royalty
        collection::create_unlimited_collection(
            &resource_account, 
            string::utf8(DIGI_PET_COLLECTION_DESCRIPTION),
            string::utf8(DIGI_PET_COLLECTION_NAME),
            option::none(),
            string::utf8(DIGI_PET_COLLECTION_URI));

        // TODO: Create an NFT collection with an unlimied supply and the following aspects: 
        //          - name: DIGI_PET_ACCESSORY_COLLECTION_NAME
        //          - description: DIGI_PET_ACCESSORY_COLLECTION_DESCRIPTION
        //          - uri: DIGI_PET_ACCESSORY_COLLECTION_URI
        //          - royalty: no royalty
        collection::create_unlimited_collection(
            &resource_account, 
            string::utf8(DIGI_PET_ACCESSORY_COLLECTION_DESCRIPTION),
            string::utf8(DIGI_PET_ACCESSORY_COLLECTION_NAME),
            option::none(),
            string::utf8(DIGI_PET_ACCESSORY_COLLECTION_URI)
        );

        // TODO: Create fungible token for digi pet food 
        // 
        // HINT: Use helper function - create_food_fungible_token 
        create_food_token(&resource_account);
        // TODO: Create the State global resource and move it to the resource account
        let state = State {
            signer_cap: resource_signer_cap,
            pet_count: 0, 
            adopt_pet_events: account::new_event_handle<AdoptPetEvent>(account),
            feed_pet_events: account::new_event_handle<FeedPetEvent>(account),
            play_with_pet_events: account::new_event_handle<PlayWithPetEvent>(account),
            bury_pet_events: account::new_event_handle<BuryPetEvent>(account)         
        };

        move_to(&resource_account, state);
    }

    /* 
        Mints a new DigiPetToken for the adopter account
        @param adopter - signer representing the account adopting the new pet
        @param pet_name - name of the pet to be adopted
        @param pet_type_code - code which specifies the type of digi-pet that is being adopted
    */
    public entry fun adopt_pet(
        adopter: &signer,
        pet_name: String, 
        pet_type_code: u64
    ) acquires State {
        // TODO: Create the pet token's name based off the State's pet_count. Increment the pet 
        //          count as well.
        //
        // HINT: Use this formatting - "Pet #{}", where {} is the pet_count + 1
        let state_ref = borrow_global_mut<State>(get_resource_account_address());
        let new_pet_count = state_ref.pet_count + 1;
        state_ref.pet_count = new_pet_count;
        let pet_token_name = string_utils::format2(&b"Pet #{}: {}", new_pet_count, pet_name);

        // TODO: Create a new named token with the following aspects: 
        //          - collection name: DIGI_PET_COLLECTION_NAME
        //          - token description: DIGI_PET_TOKEN_DESCRIPTION
        //          - token name: Specified in above TODO
        //          - royalty: no royalty
        //          - uri: DIGI_PET_TOKEN_URI
        let creator = account::create_signer_with_capability(&state_ref.signer_cap);

        let token_ref = token::create_named_token(
            &creator,
            string::utf8(DIGI_PET_COLLECTION_NAME),
            string::utf8(DIGI_PET_TOKEN_DESCRIPTION),
            pet_token_name,
            option::none(),
            string::utf8(DIGI_PET_TOKEN_URI)
        );

        // TODO: Transfer the token to the adopter account
        let pet_address = get_pet_token_address_with_token_name(pet_token_name);
        let pet_token_object = object::address_to_object<token::Token>(pet_address);
        let adopter_address = signer::address_of(adopter);
        object::transfer<token::Token>(&creator, pet_token_object, adopter_address);

        // TODO: Create the property_map for the new token with the following properties: 
        //          - PROPERTY_KEY_PET_NAME: the name of the pet (same as token name)
        //          - PROPERTY_KEY_PET_TYPE: the type of pet (string)
        //          - PROPERTY_KEY_PET_HEALTH: the health level of the pet (use STARTING_VALUE_PET_HEALTH)
        //          - PROPERTY_KEY_PET_HAPPINESS: the happiness level of the pet (use STARTING_VALUE_PET_HAPPINESS)
        //          - PROPERTY_KEY_PET_BIRTHDAY_TIMESTAMP_SECONDS: the current timestamp
        //          - PROPERTY_KEY_LAST_TIMESTAMP_FED: the current timestamp
        //          - PROPERTY_KEY_LAST_TIMESTAMP_PLAYED_WITH: the current timestamp
        //          - PROPERTY_KEY_LAST_TIMESTAMP_UPDATED: the current timestamp
        let current_time = timestamp::now_seconds();
        let input = property_map::prepare_input(
            vector[
                string::utf8(PROPERTY_KEY_PET_NAME),
                string::utf8(PROPERTY_KEY_PET_TYPE),
                string::utf8(PROPERTY_KEY_PET_HEALTH),
                string::utf8(PROPERTY_KEY_PET_HAPPINESS),
                string::utf8(PROPERTY_KEY_PET_BIRTHDAY_TIMESTAMP_SECONDS),
                string::utf8(PROPERTY_KEY_LAST_TIMESTAMP_FED),
                string::utf8(PROPERTY_KEY_LAST_TIMESTAMP_PLAYED_WITH),
                string::utf8(PROPERTY_KEY_LAST_TIMESTAMP_UPDATED),
            ],
            vector[
                string::utf8(b"0x1::string::String"),
                string::utf8(b"0x1::string::String"),
                string::utf8(b"u64"),
                string::utf8(b"u64"),
                string::utf8(b"u64"),
                string::utf8(b"u64"),
                string::utf8(b"u64"),
                string::utf8(b"u64"),
            ],
            vector[
                bcs::to_bytes<String>(&pet_name),
                bcs::to_bytes<vector<u8>>(&*vector::borrow(&PET_TYPES, pet_type_code)),
                bcs::to_bytes<u64>(&STARTING_VALUE_PET_HEALTH),
                bcs::to_bytes<u64>(&STARTING_VALUE_PET_HAPPINESS),
                bcs::to_bytes<u64>(&current_time),
                bcs::to_bytes<u64>(&current_time),
                bcs::to_bytes<u64>(&current_time),
                bcs::to_bytes<u64>(&current_time),
            ],
        );
        property_map::init(&token_ref, input);

        // TODO: Create the DigiPetToken object and move it to the new token object signer
        let digi_pet_token = DigiPetToken {
            mutator_ref: token::generate_mutator_ref(&token_ref),
            burn_ref: token::generate_burn_ref(&token_ref),
            property_mutator_ref: property_map::generate_mutator_ref(&token_ref), 
            toys: vector::empty<Toy>()
        };
        let object_signer = object::generate_signer(&token_ref);
        move_to(&object_signer, digi_pet_token);

        // TODO: Emit a new AdoptPetEvent
        let event = AdoptPetEvent {
            adopter: adopter_address, 
            pet_name: pet_token_name, 
            pet: pet_address,
            pet_type: string::utf8(*vector::borrow(&PET_TYPES, pet_type_code)),       
        };
        event::emit_event(&mut state_ref.adopt_pet_events, event);
    }

    /* 
        Mints food tokens in exchange for apt
        @param buyer - signer representing the buyer of the food tokens
        @param amount - amount of food tokens to purchase
    */
    public entry fun buy_pet_food(buyer: &signer, amount: u64) acquires AccessoryToken {
        // TODO: Ensure the buyer has enough APT
        //
        // HINT: 
        //      - Use check_if_user_has_enough_apt function below
        //      - Use `amount` and FOOD_TOKEN_PRICE to calculate the correct amount of APT to check
        let buyer_address = signer::address_of(buyer);
        let apt_needed = amount * FOOD_TOKEN_PRICE;
        check_if_user_has_enough_apt(buyer_address, apt_needed);

        // TODO: Transfer the correct amount of APT from the buyer to the module's resource account
        //
        // HINT: Use `amount` and FOOD_TOKEN_PRICE to calculate the correct amount of APT to transfer
        coin::transfer<AptosCoin>(buyer, get_resource_account_address(), apt_needed);

        // TODO: Mint `amount` of food tokens to the buyer
        //
        // HINT: Use the mint_fungible_token_internal function
        mint_fungible_token_internal(food_token_address(), amount, buyer_address);
    }

    /* 
        Creates a new Toy resource for the buyer's pet
        @param buyer - signer representing the account that is buying a toy for their pet
        @param pet - address of the pet to buy a toy for
    */
    public entry fun buy_pet_toy(buyer: &signer, pet: address) acquires DigiPetToken {
        // TODO: Ensure the buyer owns the pet
        //
        // HINT: 
        //      - Use check_if_user_owns_pet function below
        let buyer_address = signer::address_of(buyer);
        check_if_user_owns_pet(buyer_address, pet);

        // TODO: Ensure the buyer has enough APT
        //
        // HINT: 
        //      - Use check_if_user_has_enough_apt function below
        //      - Use TOY_PRICE_APT as the amount of APT to transfer
        check_if_user_has_enough_apt(buyer_address, TOY_PRICE_APT);

        // TODO: Transfer the correct amount of APT from the buyer to the module's resource account
        //
        // HINT: Use TOY_PRICE_APT as the amount of APT to transfer
        coin::transfer<AptosCoin>(buyer, get_resource_account_address(), TOY_PRICE_APT);

        // TODO: Get the correct toy name based on the token's pet_type property
        //
        // HINT: Use the get_toy_name function
        let pet_token_object = object::address_to_object<token::Token>(pet);
        let toy_name = get_toy_name(property_map::read_string(&pet_token_object, &string::utf8(PROPERTY_KEY_PET_TYPE))); 

        // TODO: Create a new toy object with the correct name and durability and push it to the 
        //          pet's toy list
        //
        // HINT: Use STARTING_TOY_DURABILITY for the durability
        let new_toy = Toy {
            name: toy_name,
            durability: STARTING_TOY_DURABILITY          
        };

        let digi_pet_token_ref = borrow_global_mut<DigiPetToken>(pet);
        vector::push_back(&mut digi_pet_token_ref.toys, new_toy);
    }

    /* 
        Burn food tokens to increase the health of a pet
        @param owner - signer representing the owner of the pet
        @param pet_to_feed - address of the pet to be fed
        @param amount_to_feed - amount of food tokens to feed the pet
    */
    public entry fun feed_pet(
        owner: &signer,
        pet_to_feed: address,
        amount_to_feed: u64
    ) acquires State, DigiPetToken, AccessoryToken {
        // TODO: Ensure the owner owns the pet
        //
        // HINT: 
        //      - Use check_if_user_owns_pet function below
        let owner_address = signer::address_of(owner);
        check_if_user_owns_pet(owner_address, pet_to_feed);
        
        // TODO: Ensure the buyer has enough food to feed the pet
        //
        // HINT: 
        //      - Use check_if_user_has_enough_food function below
        check_if_user_has_enough_food(owner_address, amount_to_feed);

        // TODO: Update the pet status. If the pet is dead, call bury_pet and return
        //
        // HINT: Use the update_pet_stats function 
        let pet_stat = update_pet_stats(pet_to_feed);
        if (!pet_stat) {
            bury_pet(pet_to_feed);
            return
        };

        // TODO: Burn the correct amount of food tokens
        // 
        // HINT: Use the burn_fungible_token_internal function
        burn_fungible_token_internal(owner, food_token_address(), amount_to_feed);

        // TODO: Add the amount of food to the pet's PROPERTY_KEY_PET_HEALTH
        let digi_pet_token_ref = borrow_global<DigiPetToken>(pet_to_feed);
        let pet_token_object = object::address_to_object<token::Token>(pet_to_feed);
        let pet_health = property_map::read_u64(&pet_token_object, &string::utf8(PROPERTY_KEY_PET_HEALTH)) + amount_to_feed;
        property_map::update(
            &digi_pet_token_ref.property_mutator_ref, 
            &string::utf8(PROPERTY_KEY_PET_HEALTH), 
            string::utf8(b"u64"), 
            bcs::to_bytes<u64>(&pet_health)
        );

        // TODO: Update the pet's PROPERTY_KEY_LAST_TIMESTAMP_FED
        property_map::update(
            &digi_pet_token_ref.property_mutator_ref, 
            &string::utf8(PROPERTY_KEY_LAST_TIMESTAMP_FED), 
            string::utf8(b"u64"), 
            bcs::to_bytes<u64>(&timestamp::now_seconds())
        );

        // TODO: Emit a new FeedPetEvent
        let state_ref = borrow_global_mut<State>(get_resource_account_address());
        let event = FeedPetEvent {
            owner: owner_address, 
            pet: pet_to_feed    
        };
        event::emit_event(&mut state_ref.feed_pet_events, event);
    }

    /* 
        Reset the pet's happiness
        @param owner - signer representing the owner of the pet
        @param pet_to_play_with - address of the pet to be played with
    */
    public entry fun play_with_pet(owner: &signer, pet_to_play_with: address) acquires State, DigiPetToken {
        // TODO: Ensure the owner owns the pet
        //
        // HINT: 
        //      - Use check_if_user_owns_pet function below
        let owner_address = signer::address_of(owner);
        check_if_user_owns_pet(owner_address, pet_to_play_with);

        // TODO: Update the pet status. If the pet is dead, call bury_pet and return
        //
        // HINT: Use the update_pet_stats function
        let pet_stat = update_pet_stats(pet_to_play_with);
        if (!pet_stat) {
            bury_pet(pet_to_play_with);
            return
        };

        // TODO: Set the pet's PROPERTY_KEY_PET_HAPPINESS to 150
        // TODO: Update the pet's PROPERTY_KEY_LAST_TIMESTAMP_PLAYED_WITH
        let digi_pet_token_ref = borrow_global<DigiPetToken>(pet_to_play_with);

        property_map::update(
            &digi_pet_token_ref.property_mutator_ref, 
            &string::utf8(PROPERTY_KEY_PET_HAPPINESS), 
            string::utf8(b"u64"), 
            bcs::to_bytes<u64>(&150u64)
        );
        property_map::update(
            &digi_pet_token_ref.property_mutator_ref, 
            &string::utf8(PROPERTY_KEY_LAST_TIMESTAMP_PLAYED_WITH), 
            string::utf8(b"u64"), 
            bcs::to_bytes<u64>(&timestamp::now_seconds())
        );

        // TODO: Emit a new PlayWithPetEvent
        let state_ref = borrow_global_mut<State>(get_resource_account_address());
        let event = PlayWithPetEvent{
            owner: owner_address, 
            pet: pet_to_play_with
        };
        event::emit_event(&mut state_ref.play_with_pet_events, event);     
    }

    /* 
        Update's a pet's stats. Will bury the pet if the pet has died. A pet can be updated by 
        anyone.
        @param pet - address of the pet to be updated
    */
    public entry fun update_pet_stats_entry(pet: address) acquires State, DigiPetToken {
        // TODO: Update the pet status. If the pet is dead, call bury_pet and return
        //
        // HINT: Use the update_pet_stats function
        let pet_stat = update_pet_stats(pet);

        if (!pet_stat) {
            bury_pet(pet);
            return
        }
    }

    //==============================================================================================
    // Helper functions
    //==============================================================================================

    /* 
        Fetches the toy name for the given type of pet
        @param pet_type - string representing the type of pet
        @return - the name of the toy for the given pet type
    */
    inline fun get_toy_name(pet_type: String): String {
        // TODO: Return the correct toy name based on the type of pet: 
        //          - "Dog": TOY_FOR_DOG
        //          - "Cat": TOY_FOR_CAT
        //          - "Snake": TOY_FOR_SNAKE
        //          - "Monkey": TOY_FOR_MONKEY
        //
        // HINT: Abort with code: EInvalidPetType, if pet_type is not any of the above types
        let _name = string::utf8(b"");
        if (pet_type == string::utf8(b"Dog")) {
            _name = string::utf8(TOY_FOR_DOG)
        } else if (pet_type == string::utf8(b"Cat")) {
            _name = string::utf8(TOY_FOR_CAT)
        } else if (pet_type == string::utf8(b"Snake")) {
            _name = string::utf8(TOY_FOR_SNAKE)
        } else if (pet_type == string::utf8(b"Monkey")) {
            _name = string::utf8(TOY_FOR_MONKEY)
        } else {
            abort EInvalidPetType
        };

        _name

    }

    /* 
        Update the pet's stats, and returns true if the pet is still alive and false otherwise.
        @param pet - address of the pet to update
        @return - true if the pet is still alive and false otherwise.
    */
    inline fun update_pet_stats(
        pet: address
    ): bool acquires DigiPetToken {
        // TODO: Fetch the PROPERTY_KEY_LAST_TIMESTAMP_FED and PROPERTY_KEY_PET_HEALTH properties 
        //          and calculate the amount of health to decrease from the pet
        // 
        // HINT: Use this formula to calculate the amount of health: 
        //          health to decrease = time since last fed * 100 / DAY_IN_SECONDS
        let is_alive = true;
        let pet_token_object = object::address_to_object<token::Token>(pet);
        let time_last_fed = property_map::read_u64(&pet_token_object, &string::utf8(PROPERTY_KEY_LAST_TIMESTAMP_FED));
        let health_to_decrease = (timestamp::now_seconds() - time_last_fed) * 100 / DAY_IN_SECONDS;

        // TODO: If the pet's current health is greater than the health to decrease, update the 
        //          pet's health (PROPERTY_KEY_PET_HEALTH) with the new health. Otherwise, set the 
        //          health to 0. 
        //
        // HINT: 
        //      - new health = old health - heal to decrease
        //      - the 'return' keyword is not allowed in inline functions, use other ways to return 
        //          values
        let token_ref = borrow_global_mut<DigiPetToken>(pet);
        let current_health = property_map::read_u64(&pet_token_object, &string::utf8(PROPERTY_KEY_PET_HEALTH));
        if (current_health > health_to_decrease) {
            current_health = current_health - health_to_decrease;
            property_map::update(
                &token_ref.property_mutator_ref, 
                &string::utf8(PROPERTY_KEY_PET_HEALTH), 
                string::utf8(b"u64"), 
                bcs::to_bytes<u64>(&current_health));
        } else {
            is_alive = false; //pet is dead
        };

        // TODO: Fetch the PROPERTY_KEY_LAST_TIMESTAMP_PLAYED_WITH and 
        //          PROPERTY_KEYPROPERTY_KEY_PET_HAPPINESS_PET_HEALTH properties and calculate the 
        //          amount of happiness to decrease from the pet
        // 
        // HINT: Use this formula to calculate the amount of health: 
        //          health to decrease = time since last played with * 100 / DAY_IN_SECONDS
        let current_happiness = property_map::read_u64(&pet_token_object, &string::utf8(PROPERTY_KEY_PET_HAPPINESS));
        let time_last_played = property_map::read_u64(&pet_token_object, &string::utf8(PROPERTY_KEY_LAST_TIMESTAMP_PLAYED_WITH)); 
        let happiness_to_decrease = (timestamp::now_seconds() - time_last_played) * 100 / DAY_IN_SECONDS;
        
        // TODO: While the pet has toys and until the amount of happiness to decrease is not 0, pull
        //          toys from the pet's toy list and subtract the toy's durability from the amount 
        //          of happiness to decrease. If the amount of happiness to decrease is less than a 
        //          toy's durability, subtract the amount from the durability and push it back to 
        //          the toy list.
        //
        // HINT: If the pet has any toys at all, update the PROPERTY_KEY_LAST_TIMESTAMP_PLAYED_WITH 
        //          with the current timestamp.
        let number_of_toys = vector::length(&token_ref.toys);
        if (number_of_toys > 0) {
             property_map::update(
                &token_ref.property_mutator_ref, 
                &string::utf8(PROPERTY_KEY_LAST_TIMESTAMP_PLAYED_WITH), 
                string::utf8(b"u64"), 
                bcs::to_bytes<u64>(&timestamp::now_seconds())
            );

            let total_durability = 0;
            vector::for_each<Toy>(token_ref.toys, |toy| {
                let toy : Toy = toy;
                total_durability = total_durability + toy.durability;
             });
            if (happiness_to_decrease >= total_durability) {
                happiness_to_decrease = happiness_to_decrease - total_durability;
                total_durability = 0; //used all toys'durability
            } else {
                total_durability = total_durability - happiness_to_decrease;
                happiness_to_decrease = 0;
            };

            if (total_durability == 0) {
                token_ref.toys = vector::empty();
            } else {
                vector::trim(&mut token_ref.toys, 1); //leave just one toy to store the remaining durability
                let toy = vector::borrow_mut(&mut token_ref.toys, 0);
              
                toy.durability = total_durability;
            };
        };

        // TODO: If the pet's current happiness is greater than the happiness to decrease, update 
        //          the pet's happiness (PROPERTY_KEY_PET_HAPPINESS) with the new health. Otherwise,
        //          set the happiness to 0. 
        //
        // HINT: 
        //      - new happiness = old happiness - happiness to decrease
        //      - the 'return' keyword is not allowed in inline functions, use other ways to return 
        //          values
        if (current_happiness > happiness_to_decrease) {
            current_happiness = current_happiness - happiness_to_decrease;
            property_map::update(
                &token_ref.property_mutator_ref, 
                &string::utf8(PROPERTY_KEY_PET_HAPPINESS), 
                string::utf8(b"u64"), 
                bcs::to_bytes<u64>(&current_happiness)
            );
        } else {
            is_alive = false; //0 happiness, pet is dead
        };

        // TODO: Update the PROPERTY_KEY_LAST_TIMESTAMP_UPDATED property with the current timestamp
        property_map::update(
                &token_ref.property_mutator_ref, 
                &string::utf8(PROPERTY_KEY_LAST_TIMESTAMP_UPDATED), 
                string::utf8(b"u64"), 
                bcs::to_bytes<u64>(&timestamp::now_seconds())
        );

        // TODO: Return true if the pet is still alive and false otherwise.
        is_alive
    }

    /* 
        Burns the specified pet token
        @param pet_to_bury - address of the pet token to burn
    */
    inline fun bury_pet(pet_to_bury: address) acquires State, DigiPetToken {
        // TODO: Move DigiPetToken from the pet address and destructure it
        let DigiPetToken {        
            mutator_ref: _,
            burn_ref: bref,
            property_mutator_ref: pmref, 
            toys: _} = move_from<DigiPetToken>(pet_to_bury);

        let state_ref = borrow_global_mut<State>(get_resource_account_address());
        let pet_object = object::address_to_object<token::Token>(pet_to_bury);
        let owner_address = object::owner(pet_object);
        // TODO: Burn the token's property_map and the token
        //
        // HINT: Use property_map::burn and token::burn
        property_map::burn(pmref);
        token::burn(bref);

        // TODO: Emit a new BuryPetEvent
        let event = BuryPetEvent{
            owner: owner_address, 
            pet: pet_to_bury
        };
        event::emit_event(&mut state_ref.bury_pet_events, event);     
    }

    /* 
        Mints fungible tokens for an address
        @param token_address - address of the fungible token to mint more of
        @param amount - amount of fungible tokens to minted
        @param buyer_address - address for the fungible tokens to be transferred to
    */
    inline fun mint_fungible_token_internal(
        token_address: address, 
        amount: u64, 
        buyer_address: address
    ) acquires AccessoryToken {
        // TODO: Fetch the Accessory token from the token address
        let accessory_token_ref = borrow_global<AccessoryToken>(token_address);

        // TODO: Use the token's mint_ref to mint `amount` of the food token fungible asset
        // 
        // HINT: Use fungible_asset::mint
        let asset = fungible_asset::mint(&accessory_token_ref.mint_ref, amount);
        
        // TODO: Deposit the new fungible asset to the buyer
        //
        // HINT: Use primary_fungible_store::deposit
        primary_fungible_store::deposit(buyer_address, asset);
    }

    /* 
        Burns fungible tokens from an address
        @param from - address of the account to burn the tokens from
        @param token_address - address of the fungible token to be burned
        @param amount - amount of fungible tokens to burned
    */
    inline fun burn_fungible_token_internal(
        from: &signer, 
        token_address: address, 
        amount: u64
    ) acquires AccessoryToken {
        // TODO: Fetch the Accessory token from the token address
        let accessory_token_ref = borrow_global<AccessoryToken>(token_address);

        
        // TODO: Fetch the primary fungible store of the `from` account
        //
        // HINT: Use primary_fungible_store::primary_store
          
        // TODO: Burn `amount` of the food token from the primary store
        //
        // HINT: Use fungible_asset::burn_from
        let from_address = signer::address_of(from);
        primary_fungible_store::burn(&accessory_token_ref.burn_ref, from_address, amount);
    }

    /* 
        Create the fungible food token 
        @param creator - signer representing the creator of the collection
    */
    inline fun create_food_token(creator: &signer) {

        // TODO: Create a new named token with the following aspects: 
        //          - collection name: DIGI_PET_ACCESSORY_COLLECTION_NAME
        //          - token description: FOOD_TOKEN_DESCRIPTION
        //          - token name: FOOD_TOKEN_NAME
        //          - royalty: no royalty
        //          - uri: FOOD_TOKEN_URI
        let token_ref = token::create_named_token(
            creator,
            string::utf8(DIGI_PET_ACCESSORY_COLLECTION_NAME),
            string::utf8(FOOD_TOKEN_DESCRIPTION),
            string::utf8(FOOD_TOKEN_NAME),
            option::none(),
            string::utf8(FOOD_TOKEN_URI)
        );

        // TODO: Create a new property_map for the token
        let input = property_map::prepare_input(
            vector[],
            vector[],
            vector[],
        );
        property_map::init(&token_ref, input);
        
        // TODO: Create a fungible asset for the food token with the following aspects: 
        //          - max supply: no max supply
        //          - name: FOOD_TOKEN_DESCRFOOD_TOKEN_FUNGIBLE_ASSET_NAMEIPTION
        //          - symbol: FOOD_TOKEN_FUNGIBLE_ASSET_SYMBOL
        //          - decimals: FOOD_TOKEN_DECIMALS
        //          - icon uri: FOOD_TOKEN_ICON_URI
        //          - project uri: FOOD_TOKEN_PROJECT_URI

        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &token_ref,
            option::none(),
            string::utf8(FOOD_TOKEN_FUNGIBLE_ASSET_NAME),
            string::utf8(FOOD_TOKEN_FUNGIBLE_ASSET_SYMBOL),
            FOOD_TOKEN_DECIMALS,
            string::utf8(FOOD_TOKEN_ICON_URI),
            string::utf8(FOOD_TOKEN_PROJECT_URI)
        );

        // TODO: Create a new AccessoryToken object and move it to the token's object signer
        let accessory_token = AccessoryToken {
            mutator_ref: property_map::generate_mutator_ref(&token_ref),
            mint_ref: fungible_asset::generate_mint_ref(&token_ref),
            burn_ref: fungible_asset::generate_burn_ref(&token_ref),
        };
        let object_signer = object::generate_signer(&token_ref);
        move_to(&object_signer, accessory_token);
    }

    /* 
        Fetchs the address of the fungible food token
        @return - address of the fungible food token
    */
    #[view]
    public fun food_token_address(): address {
        // TODO: Return the address of the food token
        let food_token_address = token::create_token_address(
            &get_resource_account_address(), 
            &string::utf8(DIGI_PET_ACCESSORY_COLLECTION_NAME), 
            &string::utf8(FOOD_TOKEN_NAME)
        );

        food_token_address    
    }

    /* 
        Fetches the balance of food token for an account
        @param owner_addr - address to check the balance of
        @return - balance of food token
    */
    #[view]
    public fun food_balance(owner_addr: address): u64 {
        // TODO: Get the object of the AccessoryToken
        let food_token_object = 
            object::address_to_object<AccessoryToken>(food_token_address());
        
        // TODO: Convert the AccessoryToken object to a Metadata object
        // 
        // HINT: Use object::convert
        let metadata = object::convert<AccessoryToken, Metadata>(food_token_object);
        
        // TODO: Create or fetch the owner's primary fungible store
        // 
        // HINT: Use primary_fungible_store::ensure_primary_store_exists
        let store = primary_fungible_store::ensure_primary_store_exists(owner_addr, metadata);
        
        // TODO: Get the balance of the fungible store
        // 
        // HINT: Use fungible_asset::balance
        fungible_asset::balance(store)
    }

    /* 
        Returns the number of toys a pet has
        @param pet - address of the pet to check
        @return - number of toys the pet has
    */
    #[view]
    public fun number_of_toys(pet: address): u64 acquires DigiPetToken {
        // TODO: Return the number of toys in the pet's DigiPetToken object
        let digi_pet_token_ref = borrow_global<DigiPetToken>(pet);
        vector::length(&digi_pet_token_ref.toys)
    } 

    /* 
        Returns the total durability of all of a pet's toys
        @param pet - address of the pet to check
        @return - The sum of durability for all toys belong to the pet
    */
    #[view]
    public fun total_toy_durability(pet: address): u64 acquires DigiPetToken {
        // TODO: Return the total sum of durability of every toy in the pet's toy list
        let total_durability = 0;
        let digi_pet_token_ref = borrow_global<DigiPetToken>(pet);

        vector::for_each<Toy>(digi_pet_token_ref.toys, |toy| {
            let toy : Toy = toy;
            total_durability = total_durability + toy.durability;
        });

        total_durability
    } 

    /* 
        Returns the address of the pet token with the given name
        @param token_name - name of the pet token
        @return - address of the pet token
    */
    #[view]
    public fun get_pet_token_address_with_token_name(token_name: String): address {
        // TODO: Return the address of the Digi-pet token with the given name
        let pet_address = token::create_token_address(
            &get_resource_account_address(), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &token_name
        );

        pet_address        
    }

    /* 
        Retrieves the address of this module's resource account
    */
    inline fun get_resource_account_address(): address {
        // TODO: Create the module's resource account address and return it
        account::create_resource_address(&@overmind, SEED)
    }

    //==============================================================================================
    // Validation functions
    //==============================================================================================

    inline fun check_if_user_has_enough_apt(user: address, amount_to_check_apt: u64) {
        // TODO: Ensure that the user's balance of apt is greater than or equal to the given amount. 
        //          If false, abort with code: EInsufficientAptBalance
        assert!(coin::balance<AptosCoin>(user) >= amount_to_check_apt, EInsufficientAptBalance);
    }

    inline fun check_if_user_has_enough_food(user: address, amount_to_check_food: u64) {
        // TODO: Ensure that the user's balance of food token is greater than or equal to the given 
        //          amount. If false, abort with code: EInsufficientFoodBalance
        assert!(food_balance(user) >= amount_to_check_food, EInsufficientFoodBalance);
    }

    inline fun check_if_user_owns_pet(user: address, pet: address) {
        // TODO: Ensure the given user is the owner of the given pet token. If not, abort with code: 
        //          ENotOwnerOfPet
        assert!(object::is_owner(object::address_to_object<token::Token>(pet), user), ENotOwnerOfPet);        
    }

    //==============================================================================================
    // Tests - DO NOT MODIFY
    //==============================================================================================


    #[test(admin = @overmind, adopter = @0xA)]
    fun test_init_module_success(
        admin: &signer, 
        adopter: &signer
    ) acquires State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        init_module(admin);

        let expected_resource_account_address = account::create_resource_address(&admin_address, b"digi-pets");
        assert!(account::exists_at(expected_resource_account_address), 0);

        let state = borrow_global<State>(expected_resource_account_address);
        assert!(
            account::get_signer_capability_address(&state.signer_cap) == expected_resource_account_address, 
            0
        );
        assert!(
            state.pet_count == 0, 
            0
        );

        assert!(
            coin::is_account_registered<AptosCoin>(expected_resource_account_address), 
            0
        );

        let expected_digi_pet_collection_address = collection::create_collection_address(
            &expected_resource_account_address, 
            &string::utf8(b"Digi-Pets collection name")
        );
        let digi_pet_collection_object = object::address_to_object<collection::Collection>(expected_digi_pet_collection_address);
        assert!(
            collection::creator<collection::Collection>(digi_pet_collection_object) == expected_resource_account_address,
            0
        );
        assert!(
            collection::name<collection::Collection>(digi_pet_collection_object) == string::utf8(b"Digi-Pets collection name"),
            0
        );
        assert!(
            collection::description<collection::Collection>(digi_pet_collection_object) == string::utf8(b"Digi-Pets collection description"),
            0
        );
        assert!(
            collection::uri<collection::Collection>(digi_pet_collection_object) == string::utf8(b"Digi-Pets collection uri"),
            0
        );

        let expected_digi_pet_accessory_collection_address = collection::create_collection_address(
            &expected_resource_account_address, 
            &string::utf8(b"Digi-Pets accessory collection name")
        );
        let digi_pet_accessory_collection_object = object::address_to_object<collection::Collection>(expected_digi_pet_accessory_collection_address);
        assert!(
            collection::creator<collection::Collection>(digi_pet_accessory_collection_object) == expected_resource_account_address,
            0
        );
        assert!(
            collection::name<collection::Collection>(digi_pet_accessory_collection_object) == string::utf8(b"Digi-Pets accessory collection name"),
            0
        );
        assert!(
            collection::description<collection::Collection>(digi_pet_accessory_collection_object) == string::utf8(b"Digi-Pets accessory collection description"),
            0
        );
        assert!(
            collection::uri<collection::Collection>(digi_pet_accessory_collection_object) == string::utf8(b"Digi-Pets accessory collection uri"),
            0
        );

        let expected_food_token_address = token::create_token_address(
            &expected_resource_account_address,
            &string::utf8(b"Digi-Pets accessory collection name"),
            &string::utf8(b"food token name")
        );
        let food_token_object = object::address_to_object<token::Token>(expected_food_token_address);
        assert!(
            token::creator(food_token_object) == expected_resource_account_address,
            0
        );
        assert!(
            token::name(food_token_object) == string::utf8(b"food token name"),
            0
        );
        assert!(
            token::description(food_token_object) == string::utf8(b"food token description"),
            0
        );
        assert!(
            token::uri(food_token_object) == string::utf8( b"food token uri"),
            0
        );

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        assert!(event::counter(&state.adopt_pet_events) == 0, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_adopt_pet_success_adopt_one_dog(
        admin: &signer, 
        adopter: &signer
    ) acquires State, DigiPetToken {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let expected_pet_type = string::utf8(b"Dog");
        let pet_code = 0;
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        timestamp::fast_forward_seconds(2000);

        let resource_account_address = account::create_resource_address(&@overmind, SEED);

        let expected_pet_token_address = token::create_token_address(
            &resource_account_address, 
            &string::utf8(b"Digi-Pets collection name"),
            &string::utf8(b"Pet #1: \"max\"")
        );
        let pet_token_object = object::address_to_object<token::Token>(expected_pet_token_address);
        assert!(
            object::is_owner(pet_token_object, adopter_address) == true, 
            0
        );
        assert!(
            token::creator(pet_token_object) == resource_account_address,
            0
        );
        assert!(
            token::name(pet_token_object) == string::utf8(b"Pet #1: \"max\""),
            0
        );
        assert!(
            token::description(pet_token_object) == string::utf8(b"Digi-Pets token description"),
            0
        );
        assert!(
            token::uri(pet_token_object) == string::utf8(b"Digi-Pets token uri"),
            0
        );
        assert!(
            option::is_none<royalty::Royalty>(&token::royalty(pet_token_object)),
            0
        );

        assert!(
            property_map::read_string(&pet_token_object, &string::utf8(b"pet_name")) 
                == expected_pet_name, 
            0
        );
        assert!(
            property_map::read_string(&pet_token_object, &string::utf8(b"pet_type")) 
                == expected_pet_type, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object, &string::utf8(b"pet_health")) 
                == 100, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object, &string::utf8(b"pet_happiness")) 
                == 100, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object, &string::utf8(b"pet_birthday")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object, &string::utf8(b"last_timestamp_fed")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object, &string::utf8(b"last_timestamp_played_with")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object, &string::utf8(b"last_timestamp_updated")) 
                == 0, 
            0
        );

        let digi_pet_token = borrow_global<DigiPetToken>(expected_pet_token_address);
        assert!(
            vector::length<Toy>(&digi_pet_token.toys) == 0,
            0
        );

        let state = borrow_global<State>(resource_account_address);
        assert!(
            state.pet_count == 1, 
            0
        );

        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_adopt_pet_success_adopt_one_cat(
        admin: &signer, 
        adopter: &signer
    ) acquires State, DigiPetToken {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        init_module(admin);

        let expected_pet_name = string::utf8(b"Charlie");
        let expected_pet_type = string::utf8(b"Cat");
        let pet_code = 1;
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        timestamp::fast_forward_seconds(2000);

        let resource_account_address = account::create_resource_address(&@overmind, SEED);

        let expected_pet_token_address = token::create_token_address(
            &resource_account_address, 
            &string::utf8(b"Digi-Pets collection name"),
            &string::utf8(b"Pet #1: \"Charlie\"")
        );
        let pet_token_object = object::address_to_object<token::Token>(expected_pet_token_address);
        assert!(
            object::is_owner(pet_token_object, adopter_address) == true, 
            0
        );
        assert!(
            token::creator(pet_token_object) == resource_account_address,
            0
        );
        assert!(
            token::name(pet_token_object) == string::utf8(b"Pet #1: \"Charlie\""),
            0
        );
        assert!(
            token::description(pet_token_object) == string::utf8(b"Digi-Pets token description"),
            0
        );
        assert!(
            token::uri(pet_token_object) == string::utf8(b"Digi-Pets token uri"),
            0
        );
        assert!(
            option::is_none<royalty::Royalty>(&token::royalty(pet_token_object)),
            0
        );

        assert!(
            property_map::read_string(&pet_token_object, &string::utf8(b"pet_name")) 
                == expected_pet_name, 
            0
        );
        assert!(
            property_map::read_string(&pet_token_object, &string::utf8(b"pet_type")) 
                == expected_pet_type, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object, &string::utf8(b"pet_health")) 
                == 100, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object, &string::utf8(b"pet_happiness")) 
                == 100, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object, &string::utf8(b"pet_birthday")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object, &string::utf8(b"last_timestamp_fed")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object, &string::utf8(b"last_timestamp_played_with")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object, &string::utf8(b"last_timestamp_updated")) 
                == 0, 
            0
        );

        let digi_pet_token = borrow_global<DigiPetToken>(expected_pet_token_address);
        assert!(
            vector::length<Toy>(&digi_pet_token.toys) == 0,
            0
        );

        let state = borrow_global<State>(resource_account_address);
        assert!(
            state.pet_count == 1, 
            0
        );

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_adopt_pet_success_adopt_one_snake(
        admin: &signer, 
        adopter: &signer
    ) acquires State, DigiPetToken {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        init_module(admin);

        let expected_pet_name = string::utf8(b"Sharon");
        let expected_pet_type = string::utf8(b"Snake");
        let pet_code = 2;
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        timestamp::fast_forward_seconds(2000);

        let resource_account_address = account::create_resource_address(&@overmind, SEED);

        let expected_pet_token_address = token::create_token_address(
            &resource_account_address, 
            &string::utf8(b"Digi-Pets collection name"),
            &string::utf8(b"Pet #1: \"Sharon\"")
        );
        let pet_token_object = object::address_to_object<token::Token>(expected_pet_token_address);
        assert!(
            object::is_owner(pet_token_object, adopter_address) == true, 
            0
        );
        assert!(
            token::creator(pet_token_object) == resource_account_address,
            0
        );
        assert!(
            token::name(pet_token_object) == string::utf8(b"Pet #1: \"Sharon\""),
            0
        );
        assert!(
            token::description(pet_token_object) == string::utf8(b"Digi-Pets token description"),
            0
        );
        assert!(
            token::uri(pet_token_object) == string::utf8(b"Digi-Pets token uri"),
            0
        );
        assert!(
            option::is_none<royalty::Royalty>(&token::royalty(pet_token_object)),
            0
        );

        assert!(
            property_map::read_string(&pet_token_object, &string::utf8(b"pet_name")) 
                == expected_pet_name, 
            0
        );
        assert!(
            property_map::read_string(&pet_token_object, &string::utf8(b"pet_type")) 
                == expected_pet_type, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object, &string::utf8(b"pet_health")) 
                == 100, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object, &string::utf8(b"pet_happiness")) 
                == 100, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object, &string::utf8(b"pet_birthday")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object, &string::utf8(b"last_timestamp_fed")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object, &string::utf8(b"last_timestamp_played_with")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object, &string::utf8(b"last_timestamp_updated")) 
                == 0, 
            0
        );

        let digi_pet_token = borrow_global<DigiPetToken>(expected_pet_token_address);
        assert!(
            vector::length<Toy>(&digi_pet_token.toys) == 0,
            0
        );

        let state = borrow_global<State>(resource_account_address);
        assert!(
            state.pet_count == 1, 
            0
        );

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_adopt_pet_success_adopt_one_monkey(
        admin: &signer, 
        adopter: &signer
    ) acquires State, DigiPetToken {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        init_module(admin);

        let expected_pet_name = string::utf8(b"Curious George");
        let expected_pet_type = string::utf8(b"Monkey");
        let pet_code = 3;
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        timestamp::fast_forward_seconds(2000);

        let resource_account_address = account::create_resource_address(&@overmind, SEED);

        let expected_pet_token_address = token::create_token_address(
            &resource_account_address, 
            &string::utf8(b"Digi-Pets collection name"),
            &string::utf8(b"Pet #1: \"Curious George\"")
        );
        let pet_token_object = object::address_to_object<token::Token>(expected_pet_token_address);
        assert!(
            object::is_owner(pet_token_object, adopter_address) == true, 
            0
        );
        assert!(
            token::creator(pet_token_object) == resource_account_address,
            0
        );
        assert!(
            token::name(pet_token_object) == string::utf8(b"Pet #1: \"Curious George\""),
            0
        );
        assert!(
            token::description(pet_token_object) == string::utf8(b"Digi-Pets token description"),
            0
        );
        assert!(
            token::uri(pet_token_object) == string::utf8(b"Digi-Pets token uri"),
            0
        );
        assert!(
            option::is_none<royalty::Royalty>(&token::royalty(pet_token_object)),
            0
        );

        assert!(
            property_map::read_string(&pet_token_object, &string::utf8(b"pet_name")) 
                == expected_pet_name, 
            0
        );
        assert!(
            property_map::read_string(&pet_token_object, &string::utf8(b"pet_type")) 
                == expected_pet_type, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object, &string::utf8(b"pet_health")) 
                == 100, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object, &string::utf8(b"pet_happiness")) 
                == 100, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object, &string::utf8(b"pet_birthday")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object, &string::utf8(b"last_timestamp_fed")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object, &string::utf8(b"last_timestamp_played_with")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object, &string::utf8(b"last_timestamp_updated")) 
                == 0, 
            0
        );

        let digi_pet_token = borrow_global<DigiPetToken>(expected_pet_token_address);
        assert!(
            vector::length<Toy>(&digi_pet_token.toys) == 0,
            0
        );

        let state = borrow_global<State>(resource_account_address);
        assert!(
            state.pet_count == 1, 
            0
        );

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_adopt_pet_success_adopt_two_monkeys(
        admin: &signer, 
        adopter: &signer
    ) acquires State, DigiPetToken {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        init_module(admin);

        let expected_pet_name_1 = string::utf8(b"Curious George");
        let expected_pet_name_2 = string::utf8(b"Harambe");
        let expected_pet_type_1 = string::utf8(b"Monkey");
        let pet_code_1 = 3;
        adopt_pet(
            adopter, 
            expected_pet_name_1,
            pet_code_1
        );
        
        timestamp::fast_forward_seconds(2000);

        adopt_pet(
            adopter, 
            expected_pet_name_2,
            pet_code_1
        );

        timestamp::fast_forward_seconds(2000);

        let resource_account_address = account::create_resource_address(&@overmind, SEED);

        let expected_pet_token_address_1 = token::create_token_address(
            &resource_account_address, 
            &string::utf8(b"Digi-Pets collection name"),
            &string::utf8(b"Pet #1: \"Curious George\"")
        );
        let pet_token_object_1 = object::address_to_object<token::Token>(expected_pet_token_address_1);
        assert!(
            object::is_owner(pet_token_object_1, adopter_address) == true, 
            0
        );
        assert!(
            token::creator(pet_token_object_1) == resource_account_address,
            0
        );
        assert!(
            token::name(pet_token_object_1) == string::utf8(b"Pet #1: \"Curious George\""),
            0
        );
        assert!(
            token::description(pet_token_object_1) == string::utf8(b"Digi-Pets token description"),
            0
        );
        assert!(
            token::uri(pet_token_object_1) == string::utf8(b"Digi-Pets token uri"),
            0
        );
        assert!(
            option::is_none<royalty::Royalty>(&token::royalty(pet_token_object_1)),
            0
        );

        assert!(
            property_map::read_string(&pet_token_object_1, &string::utf8(b"pet_name")) 
                == expected_pet_name_1, 
            0
        );
        assert!(
            property_map::read_string(&pet_token_object_1, &string::utf8(b"pet_type")) 
                == expected_pet_type_1, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"pet_health")) 
                == 100, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"pet_happiness")) 
                == 100, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"pet_birthday")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"last_timestamp_fed")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"last_timestamp_played_with")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"last_timestamp_updated")) 
                == 0, 
            0
        );

        let digi_pet_token_1 = borrow_global<DigiPetToken>(expected_pet_token_address_1);
        assert!(
            vector::length<Toy>(&digi_pet_token_1.toys) == 0,
            0
        );

        let expected_pet_token_address_2 = token::create_token_address(
            &resource_account_address, 
            &string::utf8(b"Digi-Pets collection name"),
            &string::utf8(b"Pet #2: \"Harambe\"")
        );
        let pet_token_object_2 = object::address_to_object<token::Token>(expected_pet_token_address_2);
        assert!(
            object::is_owner(pet_token_object_2, adopter_address) == true, 
            0
        );
        assert!(
            token::creator(pet_token_object_2) == resource_account_address,
            0
        );
        assert!(
            token::name(pet_token_object_2) == string::utf8(b"Pet #2: \"Harambe\""),
            0
        );
        assert!(
            token::description(pet_token_object_2) == string::utf8(b"Digi-Pets token description"),
            0
        );
        assert!(
            token::uri(pet_token_object_2) == string::utf8(b"Digi-Pets token uri"),
            0
        );
        assert!(
            option::is_none<royalty::Royalty>(&token::royalty(pet_token_object_2)),
            0
        );

        assert!(
            property_map::read_string(&pet_token_object_2, &string::utf8(b"pet_name")) 
                == expected_pet_name_2, 
            0
        );
        assert!(
            property_map::read_string(&pet_token_object_2, &string::utf8(b"pet_type")) 
                == expected_pet_type_1, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_health")) 
                == 100, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_happiness")) 
                == 100, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_birthday")) 
                == 2000, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_fed")) 
                == 2000, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_played_with")) 
                == 2000, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_updated")) 
                == 2000, 
            0
        );

        let digi_pet_token_2 = borrow_global<DigiPetToken>(expected_pet_token_address_2);
        assert!(
            vector::length<Toy>(&digi_pet_token_2.toys) == 0,
            0
        );

        let state = borrow_global<State>(resource_account_address);
        assert!(
            state.pet_count == 2, 
            0
        );

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 2, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_adopt_pet_success_adopt_multiple_species(
        admin: &signer, 
        adopter: &signer
    ) acquires State, DigiPetToken {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        init_module(admin);

        let expected_pet_name_1 = string::utf8(b"Curious George");
        let expected_pet_name_2 = string::utf8(b"Lucky");
        let expected_pet_name_3 = string::utf8(b"Charlie");
        let expected_pet_type_1 = string::utf8(b"Monkey"); 
        let expected_pet_type_2 = string::utf8(b"Dog");
        let expected_pet_type_3 = string::utf8(b"Cat");
        let pet_code_1 = 3;
        let pet_code_2 = 0;
        let pet_code_3 = 1;
        adopt_pet(
            adopter, 
            expected_pet_name_1,
            pet_code_1
        );
        
        timestamp::fast_forward_seconds(2000);

        adopt_pet(
            adopter, 
            expected_pet_name_2,
            pet_code_2
        );

        timestamp::fast_forward_seconds(6000);

        adopt_pet(
            adopter, 
            expected_pet_name_3,
            pet_code_3
        );

        timestamp::fast_forward_seconds(2000);

        let resource_account_address = account::create_resource_address(&@overmind, SEED);

        let expected_pet_token_address_1 = token::create_token_address(
            &resource_account_address, 
            &string::utf8(b"Digi-Pets collection name"),
            &string::utf8(b"Pet #1: \"Curious George\"")
        );
        let pet_token_object_1 = object::address_to_object<token::Token>(expected_pet_token_address_1);
        assert!(
            object::is_owner(pet_token_object_1, adopter_address) == true, 
            0
        );
        assert!(
            token::creator(pet_token_object_1) == resource_account_address,
            0
        );
        assert!(
            token::name(pet_token_object_1) == string::utf8(b"Pet #1: \"Curious George\""),
            0
        );
        assert!(
            token::description(pet_token_object_1) == string::utf8(b"Digi-Pets token description"),
            0
        );
        assert!(
            token::uri(pet_token_object_1) == string::utf8(b"Digi-Pets token uri"),
            0
        );
        assert!(
            option::is_none<royalty::Royalty>(&token::royalty(pet_token_object_1)),
            0
        );

        assert!(
            property_map::read_string(&pet_token_object_1, &string::utf8(b"pet_name")) 
                == expected_pet_name_1, 
            0
        );
        assert!(
            property_map::read_string(&pet_token_object_1, &string::utf8(b"pet_type")) 
                == expected_pet_type_1, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"pet_health")) 
                == 100, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"pet_happiness")) 
                == 100, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"pet_birthday")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"last_timestamp_fed")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"last_timestamp_played_with")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"last_timestamp_updated")) 
                == 0, 
            0
        );

        let digi_pet_token_1 = borrow_global<DigiPetToken>(expected_pet_token_address_1);
        assert!(
            vector::length<Toy>(&digi_pet_token_1.toys) == 0,
            0
        );

        let expected_pet_token_address_2 = token::create_token_address(
            &resource_account_address, 
            &string::utf8(b"Digi-Pets collection name"),
            &string::utf8(b"Pet #2: \"Lucky\"")
        );
        let pet_token_object_2 = object::address_to_object<token::Token>(expected_pet_token_address_2);
        assert!(
            object::is_owner(pet_token_object_2, adopter_address) == true, 
            0
        );
        assert!(
            token::creator(pet_token_object_2) == resource_account_address,
            0
        );
        assert!(
            token::name(pet_token_object_2) == string::utf8(b"Pet #2: \"Lucky\""),
            0
        );
        assert!(
            token::description(pet_token_object_2) == string::utf8(b"Digi-Pets token description"),
            0
        );
        assert!(
            token::uri(pet_token_object_2) == string::utf8(b"Digi-Pets token uri"),
            0
        );
        assert!(
            option::is_none<royalty::Royalty>(&token::royalty(pet_token_object_2)),
            0
        );

        assert!(
            property_map::read_string(&pet_token_object_2, &string::utf8(b"pet_name")) 
                == expected_pet_name_2, 
            0
        );
        assert!(
            property_map::read_string(&pet_token_object_2, &string::utf8(b"pet_type")) 
                == expected_pet_type_2, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_health")) 
                == 100, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_happiness")) 
                == 100, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_birthday")) 
                == 2000, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_fed")) 
                == 2000, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_played_with")) 
                == 2000, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_updated")) 
                == 2000, 
            0
        );

        let digi_pet_token_2 = borrow_global<DigiPetToken>(expected_pet_token_address_2);
        assert!(
            vector::length<Toy>(&digi_pet_token_2.toys) == 0,
            0
        );

        let expected_pet_token_address_3 = token::create_token_address(
            &resource_account_address, 
            &string::utf8(b"Digi-Pets collection name"),
            &string::utf8(b"Pet #3: \"Charlie\"")
        );
        let pet_token_object_3 = object::address_to_object<token::Token>(expected_pet_token_address_3);
        assert!(
            object::is_owner(pet_token_object_3, adopter_address) == true, 
            0
        );
        assert!(
            token::creator(pet_token_object_3) == resource_account_address,
            0
        );
        assert!(
            token::name(pet_token_object_3) == string::utf8(b"Pet #3: \"Charlie\""),
            0
        );
        assert!(
            token::description(pet_token_object_3) == string::utf8(b"Digi-Pets token description"),
            0
        );
        assert!(
            token::uri(pet_token_object_3) == string::utf8(b"Digi-Pets token uri"),
            0
        );
        assert!(
            option::is_none<royalty::Royalty>(&token::royalty(pet_token_object_3)),
            0
        );

        assert!(
            property_map::read_string(&pet_token_object_3, &string::utf8(b"pet_name")) 
                == expected_pet_name_3, 
            0
        );
        assert!(
            property_map::read_string(&pet_token_object_3, &string::utf8(b"pet_type")) 
                == expected_pet_type_3, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_3, &string::utf8(b"pet_health")) 
                == 100, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_3, &string::utf8(b"pet_happiness")) 
                == 100, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_3, &string::utf8(b"pet_birthday")) 
                == 8000, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_3, &string::utf8(b"last_timestamp_fed")) 
                == 8000, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_3, &string::utf8(b"last_timestamp_played_with")) 
                == 8000, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_3, &string::utf8(b"last_timestamp_updated")) 
                == 8000, 
            0
        );

        let digi_pet_token_3 = borrow_global<DigiPetToken>(expected_pet_token_address_3);
        assert!(
            vector::length<Toy>(&digi_pet_token_3.toys) == 0,
            0
        );

        let state = borrow_global<State>(resource_account_address);
        assert!(
            state.pet_count == 3, 
            0
        );

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 3, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_buy_pet_food_success_buy_food(
        admin: &signer, 
        adopter: &signer
    ) acquires AccessoryToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);

        init_module(admin);

        let expected_food_amount = 58;
        let expected_food_cost = expected_food_amount * FOOD_TOKEN_PRICE;
        aptos_coin::mint(&aptos_framework, adopter_address, expected_food_cost);
        buy_pet_food(adopter, expected_food_amount);

        let resource_account_address = account::create_resource_address(&@overmind, SEED);
        let expected_food_token_address = token::create_token_address(
            &resource_account_address,
            &string::utf8(b"Digi-Pets accessory collection name"),
            &string::utf8(b"food token name")
        );
        let food_token_object = 
            object::address_to_object<AccessoryToken>(expected_food_token_address);
        let metadata = object::convert<AccessoryToken, Metadata>(food_token_object);
        let store = primary_fungible_store::ensure_primary_store_exists(adopter_address, metadata);
        let food_token_balance = fungible_asset::balance(store);
        assert!(
            food_token_balance == expected_food_amount, 
            0
        );

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 0, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_buy_pet_food_success_buy_food_twice(
        admin: &signer, 
        adopter: &signer
    ) acquires AccessoryToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);

        init_module(admin);

        let expected_food_amount_1 = 58;
        let expected_food_cost_1 = expected_food_amount_1 * FOOD_TOKEN_PRICE;
        aptos_coin::mint(&aptos_framework, adopter_address, expected_food_cost_1);
        buy_pet_food(adopter, expected_food_amount_1);

        timestamp::fast_forward_seconds(5000);

        let expected_food_amount_2 = 1240;
        let expected_food_cost_2 = expected_food_amount_2 * FOOD_TOKEN_PRICE;
        aptos_coin::mint(&aptos_framework, adopter_address, expected_food_cost_2);
        buy_pet_food(adopter, expected_food_amount_2);

        let resource_account_address = account::create_resource_address(&@overmind, SEED);
        let expected_food_token_address = token::create_token_address(
            &resource_account_address,
            &string::utf8(b"Digi-Pets accessory collection name"),
            &string::utf8(b"food token name")
        );
        let food_token_object = 
            object::address_to_object<AccessoryToken>(expected_food_token_address);
        let metadata = object::convert<AccessoryToken, Metadata>(food_token_object);
        let store = primary_fungible_store::ensure_primary_store_exists(adopter_address, metadata);
        let food_token_balance = fungible_asset::balance(store);
        assert!(
            food_token_balance == expected_food_amount_1 + expected_food_amount_2, 
            0
        );

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 0, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    #[expected_failure(abort_code = EInsufficientAptBalance)]
    fun test_buy_pet_food_failure_insufficient_apt(
        admin: &signer, 
        adopter: &signer
    ) acquires AccessoryToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);

        init_module(admin);

        let expected_food_amount = 58;
        buy_pet_food(adopter, expected_food_amount);

        let resource_account_address = account::create_resource_address(&@overmind, SEED);
        let expected_food_token_address = token::create_token_address(
            &resource_account_address,
            &string::utf8(b"Digi-Pets accessory collection name"),
            &string::utf8(b"food token name")
        );
        let food_token_object = 
            object::address_to_object<AccessoryToken>(expected_food_token_address);
        let metadata = object::convert<AccessoryToken, Metadata>(food_token_object);
        let store = primary_fungible_store::ensure_primary_store_exists(adopter_address, metadata);
        let food_token_balance = fungible_asset::balance(store);
        assert!(
            food_token_balance == expected_food_amount, 
            0
        );

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 0, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_update_pet_stats_success_stats_updated_correctly_alive(
        admin: &signer, 
        adopter: &signer
    ) acquires DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        timestamp::fast_forward_seconds(86400 / 2); // Half a day in seconds

        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        let is_pet_alive = update_pet_stats(expected_pet_address);
        assert!(
            is_pet_alive == true, 
            0
        );

        let pet_token_object_2 = object::address_to_object<token::Token>(expected_pet_address);

        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_health")) == 50, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_happiness")) == 50, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_birthday")) == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_fed")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_played_with")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_updated")) 
                == 86400 / 2, 
            0
        );

        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_update_pet_stats_success_stats_updated_correctly_alive_with_toy (
        admin: &signer, 
        adopter: &signer
    ) acquires DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        aptos_coin::mint(&aptos_framework, adopter_address, TOY_PRICE_APT);
        buy_pet_toy(adopter, expected_pet_address);

        timestamp::fast_forward_seconds(86400 / 2); // Half a day in seconds

        let is_pet_alive = update_pet_stats(expected_pet_address);
        assert!(
            is_pet_alive == true, 
            0
        );

        let pet_token_object_2 = object::address_to_object<token::Token>(expected_pet_address);

        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_health")) == 50, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_happiness")) == 100, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_birthday")) == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_fed")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_played_with")) 
                == 86400 / 2, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_updated")) 
                == 86400 / 2, 
            0
        );

        let digi_pet_token = borrow_global<DigiPetToken>(expected_pet_address);
        assert!(
            vector::length<Toy>(&digi_pet_token.toys) == 0,
            0
        );
        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_update_pet_stats_success_stats_updated_correctly_alive_with_toy_partial_use(
        admin: &signer, 
        adopter: &signer
    ) acquires DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        aptos_coin::mint(&aptos_framework, adopter_address, TOY_PRICE_APT);
        buy_pet_toy(adopter, expected_pet_address);

        timestamp::fast_forward_seconds(86400 / 4); // quarter of a day in seconds

        let is_pet_alive = update_pet_stats(expected_pet_address);
        assert!(
            is_pet_alive == true, 
            0
        );

        let pet_token_object_2 = object::address_to_object<token::Token>(expected_pet_address);

        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_health")) == 75, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_happiness")) == 100, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_birthday")) == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_fed")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_played_with")) 
                == 86400 / 4, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_updated")) 
                == 86400 / 4, 
            0
        );

        let digi_pet_token = borrow_global<DigiPetToken>(expected_pet_address);
        assert!(
            vector::length<Toy>(&digi_pet_token.toys) == 1,
            0
        );

        let new_toy = vector::borrow<Toy>(&digi_pet_token.toys, 0);
        assert!(
            new_toy.name == string::utf8(b"Chew toy"),
            0
        );
        assert!(
            new_toy.durability == 25, 
            0
        );
        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_update_pet_stats_success_stats_updated_correctly_alive_with_multiple_toys_partial_use(
        admin: &signer, 
        adopter: &signer
    ) acquires DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        aptos_coin::mint(&aptos_framework, adopter_address, TOY_PRICE_APT);
        buy_pet_toy(adopter, expected_pet_address);
        aptos_coin::mint(&aptos_framework, adopter_address, TOY_PRICE_APT);
        buy_pet_toy(adopter, expected_pet_address);

        timestamp::fast_forward_seconds(86400 * 3 / 4); // 3/4 a day

        let is_pet_alive = update_pet_stats(expected_pet_address);
        assert!(
            is_pet_alive == true, 
            0
        );

        let pet_token_object_2 = object::address_to_object<token::Token>(expected_pet_address);

        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_health")) == 25, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_happiness")) == 100, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_birthday")) == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_fed")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_played_with")) 
                == 86400 * 3 / 4, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_updated")) 
                == 86400 * 3 / 4, 
            0
        );

        let digi_pet_token = borrow_global<DigiPetToken>(expected_pet_address);
        assert!(
            vector::length<Toy>(&digi_pet_token.toys) == 1,
            0
        );

        let new_toy = vector::borrow<Toy>(&digi_pet_token.toys, 0);
        assert!(
            new_toy.name == string::utf8(b"Chew toy"),
            0
        );
        assert!(
            new_toy.durability == 25, 
            0
        );
        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_update_pet_stats_success_pet_died(
        admin: &signer, 
        adopter: &signer
    ) acquires DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        timestamp::fast_forward_seconds(86400); // a day

        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        let is_pet_alive = update_pet_stats(expected_pet_address);
        assert!(
            is_pet_alive == false, 
            0
        );


        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_update_pet_stats_entry_success_stats_updated_correctly_alive(
        admin: &signer, 
        adopter: &signer
    ) acquires DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        timestamp::fast_forward_seconds(86400 / 2); // Half a day in seconds

        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        update_pet_stats_entry(expected_pet_address);

        let pet_token_object_2 = object::address_to_object<token::Token>(expected_pet_address);

        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_health")) == 50, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_happiness")) == 50, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_birthday")) == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_fed")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_played_with")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_updated")) 
                == 86400 / 2, 
            0
        );

        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_update_pet_stats_entry_success_stats_updated_correctly_alive_with_toy (
        admin: &signer, 
        adopter: &signer
    ) acquires DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        aptos_coin::mint(&aptos_framework, adopter_address, TOY_PRICE_APT);
        buy_pet_toy(adopter, expected_pet_address);

        timestamp::fast_forward_seconds(86400 / 2); // Half a day in seconds

        update_pet_stats_entry(expected_pet_address);

        let pet_token_object_2 = object::address_to_object<token::Token>(expected_pet_address);

        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_health")) == 50, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_happiness")) == 100, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_birthday")) == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_fed")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_played_with")) 
                == 86400 / 2, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_updated")) 
                == 86400 / 2, 
            0
        );

        let digi_pet_token = borrow_global<DigiPetToken>(expected_pet_address);
        assert!(
            vector::length<Toy>(&digi_pet_token.toys) == 0,
            0
        );
        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_update_pet_stats_entry_success_stats_updated_correctly_alive_with_toy_partial_use(
        admin: &signer, 
        adopter: &signer
    ) acquires DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        aptos_coin::mint(&aptos_framework, adopter_address, TOY_PRICE_APT);
        buy_pet_toy(adopter, expected_pet_address);

        timestamp::fast_forward_seconds(86400 / 4); // quarter of a day in seconds

        update_pet_stats_entry(expected_pet_address);

        let pet_token_object_2 = object::address_to_object<token::Token>(expected_pet_address);

        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_health")) == 75, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_happiness")) == 100, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_birthday")) == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_fed")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_played_with")) 
                == 86400 / 4, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_updated")) 
                == 86400 / 4, 
            0
        );

        let digi_pet_token = borrow_global<DigiPetToken>(expected_pet_address);
        assert!(
            vector::length<Toy>(&digi_pet_token.toys) == 1,
            0
        );

        let new_toy = vector::borrow<Toy>(&digi_pet_token.toys, 0);
        assert!(
            new_toy.name == string::utf8(b"Chew toy"),
            0
        );
        assert!(
            new_toy.durability == 25, 
            0
        );
        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_update_pet_stats_entry_success_stats_updated_correctly_alive_with_multiple_toys_partial_use(
        admin: &signer, 
        adopter: &signer
    ) acquires DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        aptos_coin::mint(&aptos_framework, adopter_address, TOY_PRICE_APT);
        buy_pet_toy(adopter, expected_pet_address);
        aptos_coin::mint(&aptos_framework, adopter_address, TOY_PRICE_APT);
        buy_pet_toy(adopter, expected_pet_address);

        timestamp::fast_forward_seconds(86400 * 3 / 4); // 3/4 a day

        update_pet_stats_entry(expected_pet_address);

        let pet_token_object_2 = object::address_to_object<token::Token>(expected_pet_address);

        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_health")) == 25, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_happiness")) == 100, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"pet_birthday")) == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_fed")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_played_with")) 
                == 86400 * 3 / 4, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_2, &string::utf8(b"last_timestamp_updated")) 
                == 86400 * 3 / 4, 
            0
        );

        let digi_pet_token = borrow_global<DigiPetToken>(expected_pet_address);
        assert!(
            vector::length<Toy>(&digi_pet_token.toys) == 1,
            0
        );

        let new_toy = vector::borrow<Toy>(&digi_pet_token.toys, 0);
        assert!(
            new_toy.name == string::utf8(b"Chew toy"),
            0
        );
        assert!(
            new_toy.durability == 25, 
            0
        );
        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_update_pet_stats_entry_success_pet_died(
        admin: &signer, 
        adopter: &signer
    ) acquires DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        timestamp::fast_forward_seconds(86400); // a day

        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        update_pet_stats_entry(expected_pet_address);

        assert!(exists<DigiPetToken>(expected_pet_address) == false, 0);


        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 1, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_bury_pet_success(
        admin: &signer, 
        adopter: &signer
    ) acquires DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        timestamp::fast_forward_seconds(86400); // a day

        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        bury_pet(expected_pet_address);

        assert!(!exists<DigiPetToken>(expected_pet_address), 0);

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 1, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_feed_pet_success_health_increased(
        admin: &signer, 
        adopter: &signer
    ) acquires AccessoryToken, DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        let expected_food_amount = 58;
        let expected_food_cost = expected_food_amount * FOOD_TOKEN_PRICE;
        aptos_coin::mint(&aptos_framework, adopter_address, expected_food_cost);
        buy_pet_food(adopter, expected_food_amount);

        feed_pet(adopter, expected_pet_address, 50);

        let pet_token_object_1 = object::address_to_object<token::Token>(expected_pet_address);

        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"pet_health")) 
                == 150, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"last_timestamp_fed")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"last_timestamp_updated")) 
                == 0, 
            0
        );
        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 1, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_feed_pet_success(
        admin: &signer, 
        adopter: &signer
    ) acquires AccessoryToken, DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        let expected_food_amount = 58;
        let expected_food_cost = expected_food_amount * FOOD_TOKEN_PRICE;
        aptos_coin::mint(&aptos_framework, adopter_address, expected_food_cost);
        buy_pet_food(adopter, expected_food_amount);

        feed_pet(adopter, expected_pet_address, 50);

        let pet_token_object_1 = object::address_to_object<token::Token>(expected_pet_address);

        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"pet_health")) 
                == 150, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"last_timestamp_fed")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"last_timestamp_updated")) 
                == 0, 
            0
        );
        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 1, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_feed_pet_success_pet_died(
        admin: &signer, 
        adopter: &signer
    ) acquires AccessoryToken, DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        timestamp::fast_forward_seconds(86400);

        let expected_food_amount = 58;
        let expected_food_cost = expected_food_amount * FOOD_TOKEN_PRICE;
        aptos_coin::mint(&aptos_framework, adopter_address, expected_food_cost);
        buy_pet_food(adopter, expected_food_amount);

        feed_pet(adopter, expected_pet_address, 50);

        assert!(!exists<DigiPetToken>(expected_pet_address), 0);
        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 1, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    #[expected_failure(abort_code = EInsufficientFoodBalance)]
    fun test_feed_pet_failure_insufficient_food(
        admin: &signer, 
        adopter: &signer
    ) acquires AccessoryToken, DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        feed_pet(adopter, expected_pet_address, 50);

        let pet_token_object_1 = object::address_to_object<token::Token>(expected_pet_address);

        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"pet_health")) 
                == 150, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"last_timestamp_fed")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"last_timestamp_updated")) 
                == 0, 
            0
        );
        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 1, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    #[expected_failure(abort_code = ENotOwnerOfPet)]
    fun test_feed_pet_failure_not_owner(
        admin: &signer, 
        adopter: &signer
    ) acquires AccessoryToken, DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(admin);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        let expected_food_amount = 58;
        let expected_food_cost = expected_food_amount * FOOD_TOKEN_PRICE;
        aptos_coin::mint(&aptos_framework, admin_address, expected_food_cost);
        buy_pet_food(admin, expected_food_amount);

        feed_pet(admin, expected_pet_address, 50);

        let pet_token_object_1 = object::address_to_object<token::Token>(expected_pet_address);

        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"pet_health")) 
                == 150, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"last_timestamp_fed")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"last_timestamp_updated")) 
                == 0, 
            0
        );
        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 1, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_play_with_pet_success_happiness_increased(
        admin: &signer, 
        adopter: &signer
    ) acquires DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        play_with_pet(adopter, expected_pet_address);

        let pet_token_object_1 = object::address_to_object<token::Token>(expected_pet_address);

        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"pet_happiness")) 
                == 150, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"last_timestamp_played_with")) 
                == 0, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"last_timestamp_updated")) 
                == 0, 
            0
        );
        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 1, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_play_with_pet_success_happiness_increased_with_time_passed(
        admin: &signer, 
        adopter: &signer
    ) acquires DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        timestamp::fast_forward_seconds(86400 / 2);

        play_with_pet(adopter, expected_pet_address);

        let pet_token_object_1 = object::address_to_object<token::Token>(expected_pet_address);

        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"pet_happiness")) 
                == 150, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"last_timestamp_played_with")) 
                == 86400 / 2, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"last_timestamp_updated")) 
                == 86400 / 2, 
            0
        );
        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 1, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }
    
    #[test(admin = @overmind, adopter = @0xA)]
    fun test_play_with_pet_success_happiness_increased_with_toy(
        admin: &signer, 
        adopter: &signer
    ) acquires DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        aptos_coin::mint(&aptos_framework, adopter_address, TOY_PRICE_APT);
        buy_pet_toy(adopter, expected_pet_address);

        timestamp::fast_forward_seconds(86400 / 4);

        play_with_pet(adopter, expected_pet_address);

        let pet_token_object_1 = object::address_to_object<token::Token>(expected_pet_address);

        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"pet_happiness")) 
                == 150, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"last_timestamp_played_with")) 
                == 86400 / 4, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"last_timestamp_updated")) 
                == 86400 / 4, 
            0
        );

        let digi_pet_token = borrow_global<DigiPetToken>(expected_pet_address);
        assert!(
            vector::length<Toy>(&digi_pet_token.toys) == 1,
            0
        );

        let new_toy = vector::borrow<Toy>(&digi_pet_token.toys, 0);
        assert!(
            new_toy.name == string::utf8(b"Chew toy"),
            0
        );
        assert!(
            new_toy.durability == 25, 
            0
        );
        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 1, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_play_with_pet_success_happiness_increased_with_toy_2(
        admin: &signer, 
        adopter: &signer
    ) acquires DigiPetToken, State, AccessoryToken {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        aptos_coin::mint(&aptos_framework, adopter_address, TOY_PRICE_APT);
        buy_pet_toy(adopter, expected_pet_address);

        let expected_food_amount = 58;
        let expected_food_cost = expected_food_amount * FOOD_TOKEN_PRICE;
        aptos_coin::mint(&aptos_framework, adopter_address, expected_food_cost);
        buy_pet_food(adopter, expected_food_amount);

        feed_pet(adopter, expected_pet_address, 50);

        timestamp::fast_forward_seconds(86400);
        
        play_with_pet(adopter, expected_pet_address);

        let pet_token_object_1 = object::address_to_object<token::Token>(expected_pet_address);

        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"pet_happiness")) 
                == 150, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"last_timestamp_played_with")) 
                == 86400, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"last_timestamp_updated")) 
                == 86400, 
            0
        );

        let digi_pet_token = borrow_global<DigiPetToken>(expected_pet_address);
        assert!(
            vector::length<Toy>(&digi_pet_token.toys) == 0,
            0
        );
        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 1, 2);
        assert!(event::counter(&state.play_with_pet_events) == 1, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_play_with_pet_success_pet_died(
        admin: &signer, 
        adopter: &signer
    ) acquires DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        timestamp::fast_forward_seconds(86400);

        play_with_pet(adopter, expected_pet_address);

        assert!(exists<DigiPetToken>(expected_pet_address) == false, 0);
        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 1, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    #[expected_failure(abort_code = ENotOwnerOfPet)]
    fun test_play_with_pet_failure_not_owner(
        admin: &signer, 
        adopter: &signer
    ) acquires DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        timestamp::fast_forward_seconds(86400 / 2);

        play_with_pet(admin, expected_pet_address);

        let pet_token_object_1 = object::address_to_object<token::Token>(expected_pet_address);

        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"pet_happiness")) 
                == 150, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"last_timestamp_played_with")) 
                == 86400 / 2, 
            0
        );
        assert!(
            property_map::read_u64(&pet_token_object_1, &string::utf8(b"last_timestamp_updated")) 
                == 86400 / 2, 
            0
        );
        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 1, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_buy_pet_toy_success_one_toy_for_dog(
        admin: &signer, 
        adopter: &signer
    ) acquires DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        aptos_coin::mint(&aptos_framework, adopter_address, TOY_PRICE_APT);
        buy_pet_toy(adopter, expected_pet_address);
        
        let digi_pet_token = borrow_global<DigiPetToken>(expected_pet_address);
        assert!(
            vector::length<Toy>(&digi_pet_token.toys) == 1,
            0
        );

        let new_toy = vector::borrow<Toy>(&digi_pet_token.toys, 0);
        assert!(
            new_toy.name == string::utf8(b"Chew toy"),
            0
        );
        assert!(
            new_toy.durability == 50, 
            0
        );
        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_buy_pet_toy_success_one_toy_for_cat(
        admin: &signer, 
        adopter: &signer
    ) acquires DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 1;
        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        aptos_coin::mint(&aptos_framework, adopter_address, TOY_PRICE_APT);
        buy_pet_toy(adopter, expected_pet_address);
        
        let digi_pet_token = borrow_global<DigiPetToken>(expected_pet_address);
        assert!(
            vector::length<Toy>(&digi_pet_token.toys) == 1,
            0
        );

        let new_toy = vector::borrow<Toy>(&digi_pet_token.toys, 0);
        assert!(
            new_toy.name == string::utf8(b"Yarn ball"),
            0
        );
        assert!(
            new_toy.durability == 50, 
            0
        );
        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_buy_pet_toy_success_one_toy_for_snake(
        admin: &signer, 
        adopter: &signer
    ) acquires DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 2;
        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        aptos_coin::mint(&aptos_framework, adopter_address, TOY_PRICE_APT);
        buy_pet_toy(adopter, expected_pet_address);
        
        let digi_pet_token = borrow_global<DigiPetToken>(expected_pet_address);
        assert!(
            vector::length<Toy>(&digi_pet_token.toys) == 1,
            0
        );

        let new_toy = vector::borrow<Toy>(&digi_pet_token.toys, 0);
        assert!(
            new_toy.name == string::utf8(b"Teddy bear"),
            0
        );
        assert!(
            new_toy.durability == 50, 
            0
        );
        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_buy_pet_toy_success_one_toy_for_monkey(
        admin: &signer, 
        adopter: &signer
    ) acquires DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 3;
        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        aptos_coin::mint(&aptos_framework, adopter_address, TOY_PRICE_APT);
        buy_pet_toy(adopter, expected_pet_address);
        
        let digi_pet_token = borrow_global<DigiPetToken>(expected_pet_address);
        assert!(
            vector::length<Toy>(&digi_pet_token.toys) == 1,
            0
        );

        let new_toy = vector::borrow<Toy>(&digi_pet_token.toys, 0);
        assert!(
            new_toy.name == string::utf8(b"Beach ball"),
            0
        );
        assert!(
            new_toy.durability == 50, 
            0
        );
        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_buy_pet_toy_success_two_toys_for_monkey(
        admin: &signer, 
        adopter: &signer
    ) acquires DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 3;
        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        aptos_coin::mint(&aptos_framework, adopter_address, TOY_PRICE_APT);
        buy_pet_toy(adopter, expected_pet_address);

        aptos_coin::mint(&aptos_framework, adopter_address, TOY_PRICE_APT);
        buy_pet_toy(adopter, expected_pet_address);
        
        let digi_pet_token = borrow_global<DigiPetToken>(expected_pet_address);
        assert!(
            vector::length<Toy>(&digi_pet_token.toys) == 2,
            0
        );

        let new_toy_1 = vector::borrow<Toy>(&digi_pet_token.toys, 0);
        assert!(
            new_toy_1.name == string::utf8(b"Beach ball"),
            0
        );
        assert!(
            new_toy_1.durability == 50, 
            0
        );

        let new_toy_2 = vector::borrow<Toy>(&digi_pet_token.toys, 0);
        assert!(
            new_toy_2.name == string::utf8(b"Beach ball"),
            0
        );
        assert!(
            new_toy_2.durability == 50, 
            0
        );
        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    #[expected_failure(abort_code = EInsufficientAptBalance)]
    fun test_buy_pet_toy_failure_insufficient_apt(
        admin: &signer, 
        adopter: &signer
    ) acquires DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(adopter);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        buy_pet_toy(adopter, expected_pet_address);
        
        let digi_pet_token = borrow_global<DigiPetToken>(expected_pet_address);
        assert!(
            vector::length<Toy>(&digi_pet_token.toys) == 1,
            0
        );

        let new_toy = vector::borrow<Toy>(&digi_pet_token.toys, 0);
        assert!(
            new_toy.name == string::utf8(b"Chew toy"),
            0
        );
        assert!(
            new_toy.durability == 50, 
            0
        );
        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    #[expected_failure(abort_code = ENotOwnerOfPet)]
    fun test_buy_pet_toy_failure_not_owner(
        admin: &signer, 
        adopter: &signer
    ) acquires DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(admin);
    

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        aptos_coin::mint(&aptos_framework, admin_address, TOY_PRICE_APT);
        buy_pet_toy(admin, expected_pet_address);
        
        let digi_pet_token = borrow_global<DigiPetToken>(expected_pet_address);
        assert!(
            vector::length<Toy>(&digi_pet_token.toys) == 1,
            0
        );

        let new_toy = vector::borrow<Toy>(&digi_pet_token.toys, 0);
        assert!(
            new_toy.name == string::utf8(b"Chew toy"),
            0
        );
        assert!(
            new_toy.durability == 50, 
            0
        );
        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

    #[test(admin = @overmind, adopter = @0xA)]
    fun test_transfer_pet_success(
        admin: &signer, 
        adopter: &signer
    ) acquires DigiPetToken, State {
        let admin_address = signer::address_of(admin);
        let adopter_address = signer::address_of(adopter);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(adopter_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);

        coin::register<AptosCoin>(admin);
        coin::register<AptosCoin>(adopter);

        init_module(admin);

        let expected_pet_name = string::utf8(b"max");
        let pet_code = 0;
        let expected_pet_address = token::create_token_address(
            &account::create_resource_address(&@overmind, SEED), 
            &string::utf8(DIGI_PET_COLLECTION_NAME), 
            &string::utf8(b"Pet #1: \"max\"")
        );
        adopt_pet(
            adopter, 
            expected_pet_name,
            pet_code
        );

        aptos_coin::mint(&aptos_framework, adopter_address, TOY_PRICE_APT);
        buy_pet_toy(adopter, expected_pet_address);

        let pet_token_object = object::address_to_object<token::Token>(expected_pet_address);
        object::transfer<token::Token>(adopter, pet_token_object, admin_address);

        aptos_coin::mint(&aptos_framework, admin_address, TOY_PRICE_APT);
        buy_pet_toy(admin, expected_pet_address);
        
        let digi_pet_token = borrow_global<DigiPetToken>(expected_pet_address);
        assert!(
            vector::length<Toy>(&digi_pet_token.toys) == 2,
            0
        );

        let new_toy = vector::borrow<Toy>(&digi_pet_token.toys, 0);
        assert!(
            new_toy.name == string::utf8(b"Chew toy"),
            0
        );
        assert!(
            new_toy.durability == 50, 
            0
        );
        
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let state = borrow_global<State>(account::create_resource_address(&@overmind, SEED));
        assert!(event::counter(&state.adopt_pet_events) == 1, 2);
        assert!(event::counter(&state.feed_pet_events) == 0, 2);
        assert!(event::counter(&state.play_with_pet_events) == 0, 2);
        assert!(event::counter(&state.bury_pet_events) == 0, 2);
    }

}
