module Halogen.Component
  ( Component
  , Component'
  , mkComponent
  , unComponent
  , ComponentSpec
  , ComponentHTML
  , component
  , LifecycleComponentSpec
  , lifecycleComponent
  , hoist
  , ComponentSlot'
  , ComponentSlot
  , mkComponentSlot
  , mkComponentSlot'
  , unComponentSlot
  , hoistSlot
  ) where

import Prelude

import Data.Bifunctor (class Bifunctor, lmap)
import Data.Maybe (Maybe(..))
import Data.Symbol (class IsSymbol, SProxy)
import Data.Tuple (Tuple)
import Halogen.Data.Slot (Slot, SlotStorage)
import Halogen.Data.Slot as Slot
import Halogen.HTML.Core (HTML)
import Halogen.Query.HalogenM (HalogenM)
import Halogen.Query.HalogenM as HM
import Unsafe.Coerce (unsafeCoerce)

-- | The "public" type for a component, with details of the component internals
-- | existentially hidden.
-- |
-- | - `h` is the type that will be rendered by the component, usually `HTML`
-- | - `f` is the query algebra
-- | - `i` is the input value type that will be mapped to an `f` whenever the
-- |       parent of this component renders
-- | - `o` is the type for the component's output messages
-- | - `m` is the monad used for non-component-state effects
data Component (h :: Type -> Type -> Type) (f :: Type -> Type) i o (m :: Type -> Type)

-- | Makes a `Component` from a `Component'`, existentially hiding details about
-- | the component's state and potential children.
mkComponent
  :: forall h s f ps i o m
   . Component' h s f ps i o m
  -> Component h f i o m
mkComponent = unsafeCoerce

-- | Exposes the inner details of a component to a function to produce a new
-- | result. The inner details will not be allowed to be revealed in the result
-- | of the function - the compiler will complain about an escaped skolem.
unComponent
  :: forall h f i o m r
   . (forall s ps. Component' h s f ps i o m -> r)
  -> Component h f i o m
  -> r
unComponent = unsafeCoerce

-- | The "private" type for a component.
-- |
-- | - `h` is the type that will be rendered by the component, usually `HTML`
-- | - `s` is the component's state
-- | - `f` is the query algebra for the component itself
-- | - `g` is the query algebra for child components
-- | - `p` is the slot type for addressing child components
-- | - `i` is the input value type that will be mapped to an `f` whenever the
-- |       parent of this component renders
-- | - `o` is the type for the component's output messages
-- | - `m` is the monad used for non-component-state effects
type Component' h s f ps i o m =
  { initialState :: i -> s
  , render :: s -> h (ComponentSlot h ps m (f Unit)) (f Unit)
  , eval :: f ~> HalogenM s f ps o m
  , receiver :: i -> Maybe (f Unit)
  , initializer :: Maybe (f Unit)
  , finalizer :: Maybe (f Unit)
  }

-- | A spec for a component.
-- |
-- | - `h` is the type that will be rendered by the component, usually `HTML`
-- | - `s` is the component's state
-- | - `f` is the query algebra for the component itself
-- | - `g` is the query algebra for child components
-- | - `p` is the slot type for addressing child components
-- | - `o` is the type for the component's output messages
-- | - `m` is the monad used for non-component-state effects
type ComponentSpec h s f ps i o m =
  { initialState :: i -> s
  , render :: s -> h (ComponentSlot h ps m (f Unit)) (f Unit)
  , eval :: f ~> HalogenM s f ps o m
  , receiver :: i -> Maybe (f Unit)
  }

-- | A convenience synonym for the output type of a `render` function, for a
-- | parent component that renders HTML.
type ComponentHTML f ps m = HTML (ComponentSlot HTML ps m (f Unit)) (f Unit)

-- | Builds a component that allows for children.
component
  :: forall h s f ps i o m
   . ComponentSpec h s f ps i o m
  -> Component h f i o m
component spec =
  mkComponent
    { initialState: spec.initialState
    , render: spec.render
    , eval: spec.eval
    , receiver: spec.receiver
    , initializer: Nothing
    , finalizer: Nothing
    }

-- | A spec for a parent component, including lifecycle inputs.
-- |
-- | - `h` is the type that will be rendered by the component, usually `HTML`
-- | - `s` is the component's state
-- | - `f` is the query algebra for the component itself
-- | - `g` is the query algebra for child components
-- | - `p` is the slot type for addressing child components
-- | - `o` is the type for the component's output messages
-- | - `m` is the monad used for non-component-state effects
type LifecycleComponentSpec h s f ps i o m =
  { initialState :: i -> s
  , render :: s -> h (ComponentSlot h ps m (f Unit)) (f Unit)
  , eval :: f ~> HalogenM s f ps o m
  , receiver :: i -> Maybe (f Unit)
  , initializer :: Maybe (f Unit)
  , finalizer :: Maybe (f Unit)
  }

-- | Builds a component with lifecycle inputs that allows for children.
lifecycleComponent
  :: forall h s f ps i o m
   . LifecycleComponentSpec h s f ps i o m
  -> Component h f i o m
lifecycleComponent spec =
  mkComponent
    { initialState: spec.initialState
    , render: spec.render
    , eval: spec.eval
    , receiver: spec.receiver
    , initializer: spec.initializer
    , finalizer: spec.finalizer
    }

-- | Changes the component's `m` type. A use case for this would be to interpret
-- | some `Free` monad as `Aff` so the component can be used with `runUI`.
hoist
  :: forall h f i o m m'
   . Bifunctor h
  => Functor m'
  => (m ~> m')
  -> Component h f i o m
  -> Component h f i o m'
hoist nat = unComponent \c ->
  mkComponent
    { initialState: c.initialState
    , render: lmap (hoistSlot nat) <<< c.render
    , eval: HM.hoist nat <<< c.eval
    , receiver: c.receiver
    , initializer: c.initializer
    , finalizer: c.finalizer
    }

--------------------------------------------------------------------------------

type ComponentSlot' h g i o ps m a =
  { get :: forall slot. SlotStorage ps slot -> Maybe (slot g o)
  , pop :: forall slot. SlotStorage ps slot -> Maybe (Tuple (slot g o) (SlotStorage ps slot))
  , set :: forall slot. slot g o -> SlotStorage ps slot -> SlotStorage ps slot
  , component :: Component h g i o m
  , input :: i
  , output :: o -> Maybe a
  }

data ComponentSlot (h :: Type -> Type -> Type) (ps :: # Type) (m :: Type -> Type) a

instance functorComponentSlot :: Functor (ComponentSlot h ps m) where
  map f = unComponentSlot \slot -> mkComponentSlot' $ slot { output = map f <$> slot.output }

mkComponentSlot
  :: forall h sym px ps g i o p m a
   . RowCons sym (Slot g o p) px ps
  => IsSymbol sym
  => Ord p
  => SProxy sym
  -> p
  -> Component h g i o m
  -> i
  -> (o -> Maybe a)
  -> ComponentSlot h ps m a
mkComponentSlot sym p comp input output =
  unsafeCoerce { get, pop, set, component: comp, input, output }
  where
  get :: forall slot. SlotStorage ps slot -> Maybe (slot g o)
  get = Slot.lookup sym p

  pop :: forall slot. SlotStorage ps slot -> Maybe (Tuple (slot g o) (SlotStorage ps slot))
  pop = Slot.pop sym p

  set :: forall slot. slot g o -> SlotStorage ps slot -> SlotStorage ps slot
  set = Slot.insert sym p

mkComponentSlot'
  :: forall h g i o ps m a
   . ComponentSlot' h g i o ps m a
  -> ComponentSlot h ps m a
mkComponentSlot' = unsafeCoerce

unComponentSlot
  :: forall h ps m a r
   . (forall g i o. ComponentSlot' h g i o ps m a -> r)
  -> ComponentSlot h ps m a
  -> r
unComponentSlot = unsafeCoerce

hoistSlot
  :: forall h m m' ps a
   . Bifunctor h
  => Functor m'
  => (m ~> m')
  -> ComponentSlot h ps m a
  -> ComponentSlot h ps m' a
hoistSlot nat = unComponentSlot \slot ->
  mkComponentSlot' $ slot { component = hoist nat slot.component }
