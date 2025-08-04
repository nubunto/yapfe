# Platform Fighter Journey: From Research to Implementation

## Executive Summary
This document chronicles the technical journey and research findings for developing a competitive platform fighter game. It covers netcode architecture decisions, content strategy, tooling choices, and provides a concrete implementation timeline based on real-world experience.

## Competitive Landscape Analysis: Learning from the Market

### Rivals of Aether II: The Workshop Success Story
**Community Foundation**: Built on the back of Rivals 1's workshop ecosystem. The original's custom character support created a 5-year content pipeline that directly translated to Rivals 2's launch community.

**Technical Achievements**: 
- Solid rollback netcode implementation
- Strong tournament scene from day 1
- Workshop integration that actually works

**Controversial Design Decisions**:
- **Floorhugging mechanics**: Creates situations where moves can be negative on hit, breaking fighting game intuition—landing an attack shouldn't put the attacker at disadvantage
- **Game feel shifts**: Some movement options feel "floatier" than Rivals 1, alienating veteran players
- **Risk/reward imbalances**: Certain defensive options are too strong, slowing down gameplay

**Key Lesson**: Workshop support isn't just a feature—it's a community-building strategy that compounds over time.

### Stickfigurez/A Few Quick Matches: The Rapid Validation Model
**The 35K Wishlist Phenomenon**: 
- **Development time**: 2 months from concept to Steam page
- **Platform fighter engine**: Leveraged existing tech to skip foundational development
- **Art direction**: Stick figures eliminated asset pipeline complexity
- **Marketing hook**: "Sketched out" aesthetic made development process part of the appeal

**Strategic Implications**:
- **Validation speed**: 2 months to prove market demand vs 6-12 months traditional development
- **Scope discipline**: Forced focus on core mechanics over content bloat
- **Community building**: Early wishlists created development transparency, plus strategic TikTok/YouTube shorts showcasing stick figure combat sparked viral interest that converted to wishlists

**Critical Insight**: The platform fighter engine enabled rapid prototyping, but the stick figure aesthetic was the real innovation—it made development timeline visible to players.

### Smash Ultimate: The Content Colossus Paradox
**Netcode Failure**: Despite terrible online experience, remains #1 in player count and tournament attendance.

**Success Factors Analysis**:
- **Roster size**: 89 characters = content depth competitors can't match
- **Single-player content**: World of Light, Classic Mode, Spirit Board—hundreds of hours of solo content
- **Casual appeal**: 8-player free-for-alls, items, stage morphing—accessible chaos
- **IP power**: Nintendo characters = built-in audience regardless of mechanics

**The Brutal Truth**: Technical excellence doesn't guarantee success. Content volume and IP recognition can overcome fundamental flaws.

### Combo Devils: The Roguelite Innovation Play
**Mechanics Innovation**: Roguelite co-op mode addresses platform fighter's biggest weakness—skill gap intimidation.

**Casual Player Strategy**:
- **Co-op progression**: Friends can carry each other through difficult content
- **Roguelite loops**: "Just one more run" psychology vs "I need to practice" fighting game mentality
- **Power progression**: Permanent upgrades provide sense of advancement beyond skill improvement

**Technical Architecture**: 
- **Deterministic co-op**: Rollback netcode still works with PVE content
- **Scalable difficulty**: AI opponents can be tuned for different skill levels
- **Content replayability**: Procedural generation extends content lifespan

## Technical Stack: Language Reality Check

### Odin vs The Alternatives: Honest Assessment

#### Rust: The Library Paradise with Development Friction
**The Good**:
- **backroll-rs**: Production-ready rollback implementation
- **matchbox**: Battle-tested matchmaking server
- **macroquad**: Simple rendering with hot reload... but not as seamless as Odin's raylib template

**The Reality**:
- **Hot reload complexity**: Rust's build system makes "just works" hot reload significantly harder than Odin's raylib template
- **Development velocity**: Borrow checker + complex build systems = slower iteration cycles
- **Memory management**: While safe, the mental overhead affects rapid prototyping

**Verdict**: Great libraries, but the development friction works against rapid iteration needed for fighting game prototyping.

#### C: "IDK man, C? like fuck me"
**The Honest Assessment**:
- **Memory safety**: Manual memory management without modern abstractions
- **Cross-platform**: Works everywhere but requires platform-specific code for everything
- **Ecosystem**: Mature but lacks modern conveniences
- **Development experience**: Write everything from scratch or deal with inconsistent libraries

**Translation**: C gets the job done, but why suffer when better options exist?

#### C++: "I ain't touching this w/ a 10ft pole"
**The Unfiltered Truth**:
- **Complexity explosion**: Modern C++ features vs simple fighting game requirements
- **Build system hell**: CMake, vcpkg, conan—complexity that doesn't serve the game
- **Standard library bloat**: Fighting games don't need 90% of what C++ provides
- **Cross-platform pain**: Every platform has different quirks and requirements

**Bottom line**: Fighting games need simplicity, not C++'s feature complexity.

#### Zig: The Almost-Perfect Alternative
**The Similarities**:
- **Manual memory management**: Like Odin, perfect for deterministic state
- **Cross-platform**: Good cross-platform story
- **Performance**: Comparable performance characteristics

**The Maturity Gap**:
- **Graphics ecosystem**: Odin's raylib integration is more mature than Zig's graphics options
- **Vendor libraries**: Odin has better-established vendor library ecosystem
- **Community size**: Odin's smaller but more focused game development community

**The Verdict**: Zig is close, but Odin's graphics maturity and community focus give it the edge for fighting game development.

### Odin: The Fighting Game Language
**Memory Management Reality**:
- **Manual memory with arena allocation**: Perfect for rollback state snapshots—deterministic allocation patterns
- **Zero-cost abstractions**: No garbage collection pauses during frame-perfect timing
- **Cross-platform determinism**: Same floating-point behavior on Windows, Linux, Mac

**Ecosystem Foundation**:
- **Raylib integration**: Cross-platform rendering/audio/input solved out-of-the-box
- **ENet networking**: Battle-tested UDP networking library (GGPO uses similar patterns)
- **GGPO compatibility**: Vendor libraries provide rollback-ready networking primitives

**Development Velocity**:
- **Readable codebase**: Both vendor libraries and core stdlib are human-readable
- **Learning curve**: Karl Zylinsky's Odin book + small community = fast onboarding
- **Debugging simplicity**: No complex build systems or runtime abstractions

**Community Advantage**:
- **Small but helpful**: Core community actively supports game development projects
- **Vendor library quality**: External libraries are curated and well-maintained
- **Cross-platform expertise**: Community actively tests Windows/Linux/Mac builds

**Fighting Game Specific Benefits**:
- **Deterministic math**: Critical for rollback netcode synchronization
- **Memory layout control**: Perfect for state serialization/deserialization
- **Performance predictability**: No hidden allocation or garbage collection surprises

## Core Technical Requirements

### Rollback Netcode: The Non-Negotiable
**Why rollback is essential:**
- **Muscle Memory Preservation**: Input delay destroys muscle memory in fast-paced games
- **Global Playability**: Without rollback, players 100ms+ apart cannot compete meaningfully
- **Competitive Integrity**: Frame-perfect combos require deterministic input timing
- **Spectator Experience**: Rollback enables smooth viewing without input delay

**Implementation Reality**: After implementing rollback netcode based on GGPO principles, the complexity becomes manageable when approached systematically. The key insight is that rollback isn't just netcode—it's a fundamental game architecture decision.

### Network Architecture: P2P vs Client/Server

**Peer-to-Peer Advantages:**
- Zero server costs (critical for indie viability)
- Simpler implementation for 2-player matches
- Natural fit for rollback prediction model
- Direct connection = minimal latency

**Client/Server Advantages:**
- Superior cheat prevention (authoritative server)
- Better for >2 players (3+ player matches)
- Easier matchmaking infrastructure
- Persistent player progression systems

**Verdict**: Start with P2P for initial release, migrate to hybrid model if game succeeds. The rollback implementation works identically in both architectures.

## Content Strategy

### Character Roster Philosophy
**Minimum Viable Roster**: 6-8 characters
- 3 "easy" characters (Ryu/Mario archetypes)
- 3 "intermediate" characters (zone/projectile focused)
- 2 "advanced" characters (execution-heavy)

### Accessibility for Non-FGC Players
**Key Design Decisions:**
- **Single-button specials**: Reduce execution barrier
- **Visible input buffer**: Show players their inputs are being processed
- **Simplified notation**: "Forward + A" instead of "236A"
- **Tutorial gamification**: Frame tutorials as character story modes

### Workshop Integration Strategy
**Learning from Rivals of Aether**: Custom content drove 50%+ of long-term engagement

**Technical Architecture Decision**:
- **Build workshop support from day 1**: Retrofitting content pipelines is 10x harder
- **Modular character system**: Each character = data + assets + scripts
- **Steam Workshop API integration**: Automatic distribution and versioning
- **Validation system**: Prevent broken mods from crashing games

## Technical Implementation Deep Dive

### Physics Engine: Custom Implementation
After implementing the Celeste/TowerFall physics article in Odin, here's the breakdown:

**Article Implementation Scope**:
- Basic 2D platformer physics (gravity, movement, collision)
- Pixel-perfect collision detection
- Variable height jumping
- Wall jumping mechanics
- Slope handling

**Extension to Fighting Game Requirements**:
- **Hitbox/hurtbox system**: 2-3 weeks additional development
- **State machine integration**: 1 week (combat states vs movement states)
- **Knockback physics**: 1-2 weeks (DI systems, trajectory modification)
- **Platform interactions**: 1 week (ledge systems, platform dropping)

**Total Timeline**: 6-8 weeks for production-ready fighting game physics

**Code Analysis**: The Odin implementation provides a solid foundation. Key strengths:
- Deterministic floating-point math (critical for rollback)
- Clean separation of physics vs rendering
- Efficient memory layout for rollback state storage

### Engine Architecture Options

#### 1. Platform Fighter Engine (Recommendation: **Use with Caution**)
**Pros**:
- Proven rollback implementation
- Existing character templates
- Community knowledge base

**Cons**:
- **Legal/IP concerns**: Many mechanics are patented ( Smash directional influence)
- **Creative constraints**: Engine assumptions limit design space
- **Long-term technical debt**: Hard to modify core systems

#### 2. Unity/Godot Off-the-Shelf
**Team Size Threshold**: Requires 3+ person team to leverage content pipelines effectively

**Unity Specific Concerns**:
- Deterministic physics requires custom implementation anyway
- Garbage collection causes frame drops (rollback nightmare)
- IL2CPP builds required for performance

**Godot Advantages**:
- Open source = full control
- C# performance acceptable for 2D fighting games
- Built-in networking primitives

#### 3. Custom Engine (Current Path)
**Timeline Reality Check**:
- **Month 1**: Core physics + basic rendering
- **Month 2**: Rollback netcode implementation
- **Month 3**: Character system + basic combat
- **Month 4**: Content pipeline + tools
- **Month 5**: Polish + networking optimization

**Key Insight**: The "slowest" option provides maximum long-term flexibility. Each system can be optimized specifically for fighting game requirements.

## Competitive Differentiation

### New Mechanics Research
**Investigation Areas**:
- **Movement evolution**: Wall-running, air-dash cancel systems
- **Resource mechanics**: Cooldowns vs meter management
- **Stage interaction**: Dynamic elements that affect gameplay
- **Team mechanics**: 2v2 systems that work with rollback

**Design Constraint**: Every mechanic must work identically in rollback netcode. No client-side prediction for gameplay elements.

## Action Plan: Sparking the Debate

### Phase 1: Foundation (Months 1-2)
**Technical Goals**:
- Complete physics implementation
- Basic rollback netcode functional
- Single character playable vs AI

**Discussion Points**:
- Are we comfortable with 6-month development timeline?
- P2P networking: acceptable for competitive play?
- Custom engine: are we ready for technical complexity?

### Phase 2: Content Pipeline (Months 2-3)
**Goals**:
- Character creation tools functional
- Basic workshop integration
- 3 characters minimum viable

**Critical Decision**:
- Workshop support from day 1: worth the development overhead?
- Character complexity level: simple vs complex archetypes?

### Art Direction: The Visual Identity Crisis

#### 2D Art Pipeline: The "Easier" Path That's Not Easy
**Smack Studio Reality Check**:
- **Character creation**: 2-4 weeks per character (modeling, animation, hitboxes)
- **Animation complexity**: 8-directional movement + 20+ combat animations per character
- **Asset pipeline**: Smack Studio → sprite sheets → engine integration
- **Skill requirement**: Pixel art + animation principles + fighting game readability

**Perception Problem**: 2D fighting games are viewed as "indie" regardless of quality. Players expect $10-15 pricing vs $30-40 for 3D.

**Technical Advantages**:
- **Rollback state**: 2D positions compress better (x,y vs x,y,z,rotation)
- **Deterministic rendering**: No floating-point precision issues
- **Memory efficiency**: Sprite sheets vs 3D model loading

#### 3D Art Pipeline: The "Higher Value" Trap
**Hidden Complexity**:
- **Character modeling**: 6-8 weeks per character (modeling, rigging, animation)
- **Technical requirements**: Normal maps, LOD systems, lighting consistency
- **Skill barrier**: 3D modeling + rigging + animation + shader knowledge
- **Pipeline complexity**: Blender → export pipeline → engine integration → optimization

**Perception Advantage**: 3D automatically signals "premium" to players. Higher price point acceptance.

**Rollback Implications**:
- **State synchronization**: 3D transforms (position + rotation + scale) = more rollback data
- **Animation blending**: Deterministic animation systems required
- **Visual consistency**: Frame-perfect animation sync across clients

#### 2D/3D Hybrid: The Compromise That Satisfies No One
**Implementation Reality**:
- **2D physics + 3D rendering**: Keep physics as 2D (x,y) with 3D models locked to Z=0
- **Raylib flexibility**: Handles both pipelines natively
- **Visual inconsistency**: 3D models in 2D gameplay confuse player perception

**Timeline Impact**:
- **2D pipeline**: 3-4 months total art development
- **3D pipeline**: 6-8 months total art development
- **Hybrid approach**: 5-7 months (worst of both worlds)

#### Technical Architecture: Art Independence
**Engine Reality**: Raylib's architecture means art choice affects rendering only:
- **Physics**: Remains 2D regardless of visual choice
- **Rollback**: Same netcode architecture for both
- **Input**: Identical systems regardless of visuals

**State Synchronization**:
- **2D**: 8 bytes per character (x,y,velocity_x,velocity_y)
- **3D**: 20 bytes per character (x,y,z,quaternion rotation,velocity)
- **Bandwidth impact**: Negligible for modern connections

### Phase 3: Polish & Release (Months 3-6)
**Art Direction Decision Points**:
- **2D**: Can we accept "indie" perception for faster development?
- **3D**: Do we have 3D skills or budget to hire artists?
- **Hybrid**: Are we solving the right problem with this approach?

**Questions for Discussion**:
- Steam Early Access strategy: build community vs polish concerns?
- Tournament scene: grassroots vs sponsored events?
- Cross-platform: PC first, console ports later?

### The Real Conversation Starters
1. **Timeline Reality**: Are we prepared for 6-month development with 2-person team?
2. **Technical Risk**: Custom engine vs proven solutions - risk tolerance?
3. **Business Model**: One-time purchase vs cosmetic DLC vs season passes?
4. **Community Building**: How do we attract non-fighting-game players?
5. **Long-term Vision**: Esports aspirations or indie darling success?

## Next Steps
The physics foundation exists. The rollback netcode architecture is designed. The question isn't "can we build this?"—it's "should we build it this way?" Let's debate the assumptions and find our path forward.

---
*Document created: August 2025*  
*Last updated: August 2025*  
*Status: Ready for collaborative review and debate*
