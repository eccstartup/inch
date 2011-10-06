> {-# LANGUAGE GADTs, TypeOperators, TypeFamilies, RankNTypes,
>              FlexibleInstances, StandaloneDeriving #-}

> module Kind where

> import Data.Foldable
> import Prelude hiding (any)

> import BwdFwd
> import Kit



> type TmName           = String
> type TyConName        = String
> type TmConName        = String


> data Binder where
>     Pi   :: Binder
>     All  :: Binder
>   deriving (Eq, Ord, Show)

> data VarState where
>     UserVar  :: Binder -> VarState
>     SysVar   :: VarState
>   deriving (Eq, Ord, Show)

> data TyName where
>     N :: String -> Int -> VarState -> TyName
>   deriving (Eq, Ord, Show)

> nameToString :: TyName -> String
> nameToString (N s _ _) = s

> nameToSysString :: TyName -> String
> nameToSysString (N s i _) = s ++ "_" ++ show i

> nameEq :: TyName -> String -> Bool
> nameEq (N x _ (UserVar _)) y  = x == y
> nameEq (N _ _ SysVar)  _  = False

> nameBinder :: TyName -> Maybe Binder
> nameBinder (N _ _ (UserVar b))  = Just b
> nameBinder _                    = Nothing

> data KSet
> data KNum
> data k :-> l

> data Kind k where
>     KSet   :: Kind KSet
>     KNum   :: Kind KNum
>     (:->)  :: Kind k -> Kind l -> Kind (k :-> l)
> infixr 5 :->

> deriving instance Show (Kind k)

> instance HetEq Kind where
>     hetEq KSet KSet yes _ = yes
>     hetEq KNum KNum yes _ = yes
>     hetEq (k :-> k') (l :-> l') yes no = hetEq k l (hetEq k' l' yes no) no
>     hetEq _ _ _ no = no

> class KindI t where
>     kind :: Kind t

> instance KindI KSet where
>     kind = KSet

> instance KindI KNum where
>     kind = KNum

> instance (KindI k, KindI l) => KindI (k :-> l) where
>     kind = kind :-> kind

> data SKind where
>     SKSet   :: SKind
>     SKNum   :: SKind
>     SKNat   :: SKind
>     (:-->)  :: SKind -> SKind -> SKind
>   deriving (Eq, Show)
> infixr 5 :-->


> targetsSet :: Kind k -> Bool
> targetsSet KSet       = True
> targetsSet KNum       = False
> targetsSet (_ :-> k)  = targetsSet k 

> fogKind :: Kind k -> SKind
> fogKind KSet       = SKSet
> fogKind KNum       = SKNum
> fogKind (k :-> l)  = fogKind k :--> fogKind l

> kindKind :: SKind -> Ex Kind
> kindKind SKSet       = Ex KSet
> kindKind SKNum       = Ex KNum
> kindKind SKNat       = Ex KNum
> kindKind (k :--> l)  = case (kindKind k, kindKind l) of
>                            (Ex k, Ex l) -> Ex (k :-> l)








> data BVar a k where
>     Top  :: BVar (a, k) k
>     Pop  :: BVar a k -> BVar (a, l) k

> instance Show (BVar a k) where
>     show x = '!' : show (bvarToInt x)

> instance HetEq (BVar a) where
>     hetEq Top      Top      yes _  = yes
>     hetEq (Pop x)  (Pop y)  yes no = hetEq x y yes no
>     hetEq _        _        _   no = no

> instance Eq (BVar a k) where
>     (==) = (=?=)

> instance Ord (BVar a k) where
>     Top    <= _      = True
>     Pop x  <= Pop y  = x <= y
>     Pop _  <= Top    = False


> bvarToInt :: BVar a k -> Int
> bvarToInt Top      = 0
> bvarToInt (Pop x)  = succ (bvarToInt x)



> data Var a k where
>     BVar :: BVar a k          -> Var a k
>     FVar :: TyName -> Kind k  -> Var a k

> instance Show (Var a k) where
>     show (BVar x)    = show x
>     show (FVar a _)  = show a

> instance HetEq (Var a) where
>     hetEq (FVar a k)  (FVar b l)  yes _ | a == b =
>         hetEq k l yes (error "eqVar: kinding error")
>     hetEq (BVar x)    (BVar y)    yes no = hetEq x y yes no
>     hetEq _           _           _   no = no

> instance Eq (Var a k) where
>     (==) = (=?=)

> instance Ord (Var a k) where
>     BVar x    <= BVar y    = x <= y
>     FVar a _  <= FVar b _  = a <= b
>     BVar _    <= FVar _ _  = True
>     FVar _ _  <= BVar _    = False


> varName :: Var () k -> TyName
> varName (FVar a _) = a

> varKind :: Var () k -> Kind k
> varKind (FVar _ k) = k

> varBinder :: Var () k -> Maybe Binder
> varBinder (FVar a _) = nameBinder a

> fogVar :: Var () k -> String
> fogVar = fogVar' nameToString []

> fogSysVar :: Var () k -> String
> fogSysVar = fogVar' nameToSysString []

> fogVar' :: (TyName -> String) -> [String] -> Var a k -> String
> fogVar' g _  (FVar a _)  = g a
> fogVar' _ bs (BVar x)    = bs !! bvarToInt x

> varNameEq :: Var a k -> String -> Bool
> varNameEq (FVar nom _)  y = nameEq nom y
> varNameEq (BVar _)      _ = False

> wkF :: (forall k . Var a k -> t) -> t -> Var (a, l) k' -> t
> wkF f _ (FVar a k)      = f (FVar a k)
> wkF f t (BVar Top)      = t
> wkF f _ (BVar (Pop y))  = f (BVar y)


> withBVar :: (BVar a k -> BVar b k) -> Var a k -> Var b k
> withBVar f (FVar a k)  = FVar a k
> withBVar f (BVar x)    = BVar (f x)

> wkVar :: Var a k -> Var (a, l) k
> wkVar = withBVar Pop

> wkRenaming :: (Var a k -> Var b k) -> Var (a, l) k -> Var (b, l) k
> wkRenaming g (FVar a k)      = wkVar . g $ FVar a k
> wkRenaming g (BVar Top)      = BVar Top
> wkRenaming g (BVar (Pop x))  = wkVar . g $ BVar x

> bindVar :: Var a k -> Var a l -> Var (a, k) l
> bindVar v w = hetEq v w (BVar Top) (wkVar w)

> unbindVar :: Var a k -> Var (a, k) l -> Var a l 
> unbindVar v (BVar Top)      = v
> unbindVar v (BVar (Pop x))  = BVar x
> unbindVar v (FVar a k)      = FVar a k

> wkClosedVar :: Var () k -> Var a k
> wkClosedVar (FVar a k) = FVar a k

> class FV t where
>     (<<?) :: [Var () k] -> t -> Bool

> (<?) :: FV t => Var () k -> t -> Bool
> a <? t = [a] <<? t

> instance FV (Var () l) where
>     xs <<? v = any (v =?=) xs

> instance FV a => FV [a] where
>     xs <<? as = any (xs <<?) as

> instance FV a => FV (Fwd a) where
>     xs <<? t = any (xs <<?) t

> instance FV a => FV (Bwd a) where
>     xs <<? t = any (xs <<?) t

> instance (FV a, FV b) => FV (Either a b) where
>     xs <<? Left x   = xs <<? x
>     xs <<? Right y  = xs <<? y




> data VarSuffix a b where
>     VS0    :: VarSuffix a a
>     (:<<)  :: VarSuffix a b -> Var a k -> VarSuffix a (b, k)

> renameBVarVS :: VarSuffix a b -> BVar a k -> BVar b k
> renameBVarVS VS0         x = x
> renameBVarVS (vs :<< _)  x = Pop (renameBVarVS vs x)

> renameVS :: VarSuffix a b -> Var a k -> Var b k
> renameVS _   (FVar a k)  = FVar a k
> renameVS vs  (BVar x)    = BVar (renameBVarVS vs x)

> renameVSinv :: VarSuffix a b -> Var b k -> Var a k
> renameVSinv _          (FVar a k)      = FVar a k
> renameVSinv VS0        (BVar v)        = BVar v
> renameVSinv (_ :<< v)  (BVar Top)      = v
> renameVSinv (vs :<< _) (BVar (Pop x))  = renameVSinv vs (BVar x)