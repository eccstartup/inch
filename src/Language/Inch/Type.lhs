> {-# LANGUAGE DeriveFunctor, DeriveFoldable, DeriveTraversable,
>              GADTs, TypeOperators, TypeFamilies, RankNTypes,
>              ScopedTypeVariables, FlexibleInstances,
>              StandaloneDeriving, TypeSynonymInstances,
>              MultiParamTypeClasses #-}

> module Language.Inch.Type where

> import Control.Applicative
> import Data.Foldable hiding (notElem, any)
> import qualified Data.Monoid as M
> import Data.Traversable
> import Data.List
> import Unsafe.Coerce

> import Language.Inch.Kit
> import Language.Inch.Kind

> type TyNum a  = Ty a KNum
> type TypeNum  = TyNum ()

> type Type k  = Ty () k
> type Tau     = Type KSet
> type Sigma   = Type KSet
> type Rho     = Type KSet

> type Predicate   = Pred TypeNum
> type SPredicate  = Pred SType


> data Comparator = LE | LS | GE | GR | EL
>   deriving (Eq, Ord, Show)

> compFun :: Comparator -> Integer -> Integer -> Bool
> compFun LE = (<=)
> compFun LS = (<)
> compFun GE = (>=)
> compFun GR = (>)
> compFun EL = (==)

> data Pred ty where
>     P      :: Comparator -> ty -> ty -> Pred ty
>     (:=>)  :: Pred ty -> Pred ty -> Pred ty
>   deriving (Eq, Ord, Show, Functor, Foldable, Traversable)

> (%==%), (%<=%), (%<%), (%>=%), (%>%) :: forall ty. ty -> ty -> Pred ty
> (%==%)  = P EL
> (%<=%)  = P LE
> (%<%)   = P LS
> (%>=%)  = P GE
> (%>%)   = P GR



> data UnOp = Abs | Signum
>   deriving (Eq, Ord, Show)

> unOpFun :: UnOp -> Integer -> Integer
> unOpFun Abs     = abs
> unOpFun Signum  = signum

> unOpString :: UnOp -> String
> unOpString Abs     = "abs"
> unOpString Signum  = "signum"


> data BinOp = Plus | Minus | Times | Pow | Min | Max
>   deriving (Eq, Ord, Show)

> {-
>     Mod | Pow
> -}

> binOpFun :: BinOp -> Integer -> Integer -> Integer
> binOpFun Plus   = (+)
> binOpFun Minus  = (-)
> binOpFun Times  = (*)
> binOpFun Pow    = (^)
> binOpFun Min    = min
> binOpFun Max    = max

> binOpString :: BinOp -> String
> binOpString Plus   = "+"
> binOpString Minus  = "-"
> binOpString Times  = "*"
> binOpString Pow    = "^"
> binOpString Min    = "min"
> binOpString Max    = "max"

> binOpInfix :: BinOp -> Bool
> binOpInfix Plus   = True
> binOpInfix Minus  = True
> binOpInfix Times  = True
> binOpInfix Pow    = True
> binOpInfix Min    = False
> binOpInfix Max    = False



> data TyKind where
>     TK :: Type k -> Kind k -> TyKind


> data Ty a k where
>     TyVar  :: Var a k                                       -> Ty a k
>     TyCon  :: TyConName -> Kind k                           -> Ty a k
>     TyApp  :: Ty a (l :-> k) -> Ty a l                      -> Ty a k
>     Bind   :: Binder -> String -> Kind l -> Ty (a, l) KSet  -> Ty a KSet
>     Qual   :: Ty a KConstraint -> Ty a k                    -> Ty a k
>     Arr    :: Ty a (KSet :-> KSet :-> KSet)
>     TyInt  :: Integer     -> Ty a KNum
>     UnOp   :: UnOp        -> Ty a (KNum :-> KNum)
>     BinOp  :: BinOp       -> Ty a (KNum :-> KNum :-> KNum)
>     TyComp :: Comparator  -> Ty a (KNum :-> KNum :-> KConstraint)

> deriving instance Show (Ty a k)

> instance HetEq (Ty a) where
>     hetEq (TyVar a)       (TyVar b)           yes no = hetEq a b yes no
>     hetEq (TyCon c k)     (TyCon c' k')       yes no | c == c'    = hetEq k k' yes no
>     hetEq (TyApp f s)     (TyApp f' s')       yes no = hetEq f f' (hetEq s s' yes no) no
>     hetEq (Bind b x k t)  (Bind b' x' k' t')  yes no | b == b' && x == x' = hetEq k k' (hetEq t t' yes no) no
>     hetEq (Qual p t)      (Qual p' t')        yes no | p == p'    = hetEq t t' yes no
>     hetEq Arr             Arr                 yes _  = yes
>     hetEq (TyInt i)       (TyInt j)           yes _  | i == j     = yes
>     hetEq (UnOp o)        (UnOp o')           yes _  | o == o'    = yes
>     hetEq (BinOp o)       (BinOp o')          yes _  | o == o'    = yes
>     hetEq (TyComp c)      (TyComp c')         yes _  | c == c'    = yes
>     hetEq _               _                   _   no = no

> instance Eq (Ty a k) where
>     (==) = (=?=)

> instance HetOrd (Ty a) where
>     TyVar a    <?= TyVar b    = a <?= b
>     TyVar _    <?= _          = True
>     _          <?= TyVar _    = False
>     TyCon c k  <?= TyCon d l  = c <= d && k <?= l
>     TyCon _ _  <?= _          = True
>     _          <?= TyCon _ _  = False
>     TyApp f s  <?= TyApp g t  = f <?= g && s <?= t
>     TyApp _ _  <?= _          = True
>     _          <?= TyApp _ _  = False
>     Bind b x k t  <?= Bind b' x' k' t'  = b <= b' && x <= x' && k <?= k' && t <?= unsafeCoerce t'
>     Bind _ _ _ _  <?= _                 = True
>     _             <?= Bind _ _ _ _      = False
>     Qual p s      <?= Qual q t          = p <= q && s <?= t 
>     Qual _ _      <?= _                 = True
>     _             <?= Qual _ _          = False
>     Arr           <?= _                 = True
>     _             <?= Arr               = False
>     TyInt i       <?= TyInt j           = i <= j
>     TyInt _       <?= _                 = True
>     _             <?= TyInt _           = False
>     UnOp o        <?= UnOp p            = o <= p
>     UnOp _        <?= _                 = True
>     _             <?= UnOp _            = False
>     BinOp o       <?= BinOp p           = o <= p
>     BinOp _       <?= _                 = True
>     _             <?= BinOp _           = False
>     TyComp c      <?= TyComp c'         = c <= c'

> instance Ord (Ty a k) where
>     (<=) = (<?=)


> instance Num (Ty a KNum) where
>     fromInteger  = TyInt
>     (+)          = binOp Plus
>     (*)          = binOp Times
>     (-)          = binOp Minus
>     abs          = unOp Abs
>     signum       = unOp Signum
>
>     negate (TyInt k)  = TyInt (- k)
>     negate t          = 0 - t


> data SType where
>     STyVar  :: String                              ->  SType
>     STyCon  :: TyConName                           ->  SType
>     STyApp  :: SType -> SType                      ->  SType
>     SBind   :: Binder -> String -> SKind -> SType  ->  SType
>     SQual   :: SType -> SType                      ->  SType
>     SArr    ::                                         SType
>     STyInt  :: Integer                             ->  SType
>     SUnOp   :: UnOp                                ->  SType
>     SBinOp  :: BinOp                               ->  SType
>     STyComp :: Comparator                          ->  SType
>   deriving (Eq, Show)

> instance Num SType where
>     fromInteger  = STyInt
>     (+)          = sbinOp Plus
>     (*)          = sbinOp Times
>     (-)          = sbinOp Minus
>     abs          = sunOp Abs
>     signum       = sunOp Signum

>     negate (STyInt k)  = STyInt (- k)
>     negate t           = 0 - t


> predToConstraint :: Predicate -> Type KConstraint
> predToConstraint (P c m n) = tyPred c m n

> constraintToPred :: Type KConstraint -> Maybe Predicate
> constraintToPred (Qual p q)                      = (:=>) <$> constraintToPred p <*> constraintToPred q
> constraintToPred (TyComp c `TyApp` m `TyApp` n)  = Just (P c m n)
> constraintToPred _                               = Nothing

> sConstraintToPred :: SType -> Maybe (Pred SType)
> sConstraintToPred (STyComp c `STyApp` m `STyApp` n)  = Just (P c m n)
> sConstraintToPred _                                  = Nothing


> fogTy :: Type k -> SType
> fogTy = fogTy' fogVar []

> fogSysTy :: Type k -> SType
> fogSysTy = fogTy' fogSysVar []

> fogTy' :: (forall l. Var a l -> String) -> [String] -> Ty a k -> SType
> fogTy' g _   (TyVar v)       = STyVar (g v)
> fogTy' _ _   (TyCon c _)     = STyCon c
> fogTy' g xs  (TyApp f s)     = STyApp (fogTy' g xs f) (fogTy' g xs s)
> fogTy' g xs  (Qual p t)      = SQual (fogTy' g xs p) (fogTy' g xs t)
> fogTy' _ _   Arr             = SArr
> fogTy' _ _   (TyInt i)       = STyInt i
> fogTy' _ _   (UnOp o)        = SUnOp o
> fogTy' _ _   (BinOp o)       = SBinOp o
> fogTy' _ _   (TyComp c)      = STyComp c
> fogTy' g xs  (Bind b x k t)  =
>     SBind b y (fogKind k) (fogTy' (wkF g y) (y:xs) t)
>   where
>     y = alphaConv x xs

> fogPred :: Predicate -> SPredicate
> fogPred = fogPred' fogVar []

> fogSysPred :: Predicate -> SPredicate
> fogSysPred = fogPred' fogSysVar []

> fogPred' :: (forall l. Var a l -> String) -> [String] -> Pred (Ty a KNum) -> SPredicate
> fogPred' g xs = fmap (fogTy' g xs)




> alphaConv :: String -> [String] -> String
> alphaConv x xs | x `notElem` xs = x
>                | otherwise = alphaConv (x ++ "'") xs

> getTyKind :: Type k -> Kind k
> getTyKind (TyVar v)        = varKind v
> getTyKind (TyCon _ k)      = k
> getTyKind (TyApp f _)      = kindCod (getTyKind f)
> getTyKind (TyInt _)        = KNum
> getTyKind (UnOp _)         = KNum :-> KNum
> getTyKind (BinOp _)        = KNum :-> KNum :-> KNum
> getTyKind (Qual _ t)       = getTyKind t
> getTyKind (Bind _ _ __ _)  = KSet
> getTyKind Arr              = KSet :-> KSet :-> KSet
> getTyKind (TyComp _)       = KNum :-> KNum :-> KConstraint


> (-->) :: forall a. Ty a KSet -> Ty a KSet -> Ty a KSet
> s --> t = TyApp (TyApp Arr s) t
> infixr 5 -->

> (--->) :: SType -> SType -> SType
> s ---> t = STyApp (STyApp SArr s) t
> infixr 5 --->

> (/->) :: Foldable f => f (Ty a KSet) -> Ty a KSet -> Ty a KSet
> ts /-> t = Data.Foldable.foldr (-->) t ts

> (/=>) :: Foldable f => f (Ty a KConstraint) -> Ty a KSet -> Ty a KSet
> ps /=> t = Data.Foldable.foldr Qual t ps

> unOp :: UnOp -> Ty a KNum -> Ty a KNum
> unOp o = TyApp (UnOp o)

> binOp :: BinOp -> Ty a KNum -> Ty a KNum -> Ty a KNum
> binOp o = TyApp . TyApp (BinOp o)

> sunOp :: UnOp -> SType -> SType
> sunOp o = STyApp (SUnOp o)

> sbinOp :: BinOp -> SType -> SType -> SType
> sbinOp o = STyApp . STyApp (SBinOp o)



> swapTop :: Ty ((a, k), l) x -> Ty ((a, l), k) x
> swapTop = renameTy (withBVar swapVar)
>   where
>     swapVar :: BVar ((a, k), l) x -> BVar ((a, l), k) x
>     swapVar Top            = Pop Top
>     swapVar (Pop Top)      = Top
>     swapVar (Pop (Pop x))  = Pop (Pop x)

> renameTy :: (forall k. Var a k -> Var b k) -> Ty a l -> Ty b l
> renameTy g (TyVar v)       = TyVar (g v)
> renameTy _ (TyCon c k)     = TyCon c k
> renameTy g (TyApp f s)     = TyApp (renameTy g f) (renameTy g s)
> renameTy g (Bind b x k t)  = Bind b x k (renameTy (wkRenaming g) t)
> renameTy g (Qual p t)      = Qual (renameTy g p) (renameTy g t)
> renameTy _ Arr             = Arr
> renameTy _ (TyInt i)       = TyInt i
> renameTy _ (UnOp o)        = UnOp o
> renameTy _ (BinOp o)       = BinOp o
> renameTy _ (TyComp c)      = TyComp c

> bindTy :: Var a k -> Ty a l -> Ty (a, k) l
> bindTy v = renameTy (bindVar v)

> unbindTy :: Var a k -> Ty (a, k) l -> Ty a l
> unbindTy v = renameTy (unbindVar v)

> wkTy :: Ty a k -> Ty (a, l) k
> wkTy = renameTy wkVar

> wkClosedTy :: Ty () k -> Ty a k
> wkClosedTy = renameTy wkClosedVar

> wkSubst :: (Var a k -> Ty b k) -> Var (a, l) k -> Ty (b, l) k
> wkSubst g (FVar a k)      = wkTy (g (FVar a k))
> wkSubst _ (BVar Top)      = TyVar (BVar Top)
> wkSubst g (BVar (Pop x))  = wkTy (g (BVar x))

> substTy :: (forall k . Var a k -> Ty b k) -> Ty a l -> Ty b l
> substTy g (TyVar v)       = g v
> substTy _ (TyCon c k)     = TyCon c k
> substTy g (TyApp f s)     = TyApp (substTy g f) (substTy g s)
> substTy g (Bind b x k t)  = Bind b x k (substTy (wkSubst g) t)
> substTy g (Qual p t)      = Qual (substTy g p) (substTy g t)
> substTy _ Arr             = Arr
> substTy _ (TyInt i)       = TyInt i
> substTy _ (UnOp o)        = UnOp o
> substTy _ (BinOp o)       = BinOp o
> substTy _ (TyComp c)      = TyComp c

> replaceTy :: forall a k l. Var a k -> Ty a k -> Ty a l -> Ty a l
> replaceTy a u = substTy f
>   where
>     f :: Var a k' -> Ty a k'
>     -- f b@(FVar (N _ _ (UserVar Pi)) KNum) = TyVar b -- This is a hack to avoid replacing pivars
>     f b = hetEq a b u (TyVar b)



> tyPred :: Comparator -> Ty a KNum -> Ty a KNum -> Ty a KConstraint
> tyPred c m n = TyComp c `TyApp` m `TyApp` n

> styPred :: Comparator -> SType -> SType -> SType
> styPred c m n = STyComp c `STyApp` m `STyApp` n

> simplifyTy :: Ord a => Ty a KSet -> Ty a KSet
> simplifyTy = simplifyTy' []
>   where
>     simplifyTy' :: Ord a => [Ty a KConstraint] -> Ty a KSet -> Ty a KSet
>     simplifyTy' ps (Qual p t)      = simplifyTy' (simplifyPred p:ps) t
>     simplifyTy' ps t               = nub ps /=> t

> simplifyPred :: Ty a KConstraint -> Ty a KConstraint
> simplifyPred (Qual p q) = Qual (simplifyPred p) (simplifyPred q)
> simplifyPred (TyComp c `TyApp` m `TyApp` n) = case (simplifyNum m, simplifyNum n) of
>     (TyApp (TyApp (BinOp Minus) m') n', TyInt 0)  -> mkP c m' n'
>     (TyInt 0, TyApp (TyApp (BinOp Minus) n') m')  -> mkP c m' n'
>     (m', n')                                      -> mkP c m' n'
>   where
>     mkP LE x (TyApp (TyApp (BinOp Minus) y) (TyInt 1)) = tyPred LS x y
>     mkP c' x y = tyPred c' x y
> simplifyPred t = t 

> simplifyNum :: Ty a KNum -> Ty a KNum
> simplifyNum (TyApp (TyApp (BinOp o) n) m) = case (o, simplifyNum n, simplifyNum m) of
>     (Plus,   TyInt k,  TyInt l)  -> TyInt (k+l)
>     (Plus,   TyInt 0,  m')       -> m'
>     (Plus,   n',       TyInt 0)  -> n'
>     (Plus,   TyApp (TyApp (BinOp Plus) n') (TyInt k), TyInt l)  | k == -l    -> n'
>                                                         | otherwise  -> n' + TyInt (k+l)
>     (Plus,   n',       m')       -> n' + m'
>     (Times,  TyInt k,     TyInt l)     -> TyInt (k*l)
>     (Times,  TyInt 0,     _)          -> TyInt 0
>     (Times,  TyInt 1,     m')          -> m'
>     (Times,  TyInt (-1),  m')          -> negate m'
>     (Times,  _,           TyInt 0)     -> TyInt 0
>     (Times,  n',          TyInt 1)     -> n'
>     (Times,  n',          TyInt (-1))  -> negate n'
>     (Times,  n',          m')          -> n' * m'
>     (_,      n',          m')          -> TyApp (TyApp (BinOp o) n') m'
> simplifyNum t = t


> args :: Ty a k -> Int
> args (TyApp (TyApp Arr _) t)  = succ $ args t
> args (Bind Pi  _ _ t)                = succ $ args t
> args (Bind All _ _ t)               = args t
> args (Qual _ t)                     = args t
> args _                              = 0

> splitArgs :: Ty a k -> ([Ty a k], Ty a k)
> splitArgs (TyApp (TyApp Arr s) t) = (s:ss, ty)
>   where (ss, ty) = splitArgs t
> splitArgs t = ([], t)

> targets :: Ty a k -> TyConName -> Bool
> targets (TyCon c _)               t | c == t = True
> targets (TyApp (TyApp Arr _) ty)  t = targets ty t
> targets (TyApp f _)               t = targets f t
> targets (Bind _ _ _ ty)           t = targets ty t
> targets (Qual _ ty)               t = targets ty t
> targets _                         _ = False


> {-
> elemsTy :: [Var a k] -> Ty a l -> Bool
> elemsTy as (TyVar b)       = any (b =?=) as
> elemsTy as (TyApp f s)     = elemsTy as f || elemsTy as s
> elemsTy as (Bind _ _ _ t)  = elemsTy (map wkVar as) t
> elemsTy as (Qual p t)      = elemsTy as p || elemsTy as t 
> elemsTy _  _               = False

> elemTy :: Var a k -> Ty a l -> Bool
> elemTy a t = elemsTy [a] t

> elemsPred :: [Var a k] -> Pred (Ty a KNum) -> Bool
> elemsPred as = M.getAny . foldMap (M.Any . elemsTy as)

> elemPred :: Var a k -> Pred (Ty a KNum) -> Bool
> elemPred a p = elemsPred [a] p
> -}

> elemTarget :: Var a k -> Ty a l -> Bool
> elemTarget a (TyApp (TyApp Arr _) ty)  = elemTarget a ty
> elemTarget a (Qual _ ty)               = elemTarget a ty
> elemTarget a (Bind Pi _ _ ty)          = elemTarget (wkVar a) ty
> elemTarget a t                         = a <? t

> instance FV t a => FV (Pred t) a where
>     fvFoldMap f = foldMap (fvFoldMap f)
        
> instance a ~ b => FV (Ty a k) b where
>     fvFoldMap f (TyVar a)       = f a
>     fvFoldMap _ (TyCon _ _)     = M.mempty
>     fvFoldMap f (TyApp t u)     = fvFoldMap f t <.> fvFoldMap f u
>     fvFoldMap f (Bind _ _ _ t)  = fvFoldMap (wkF f M.mempty) t
>     fvFoldMap f (Qual p t)      = fvFoldMap f p <.> fvFoldMap f t
>     fvFoldMap _ Arr             = M.mempty
>     fvFoldMap _ (TyInt _)       = M.mempty
>     fvFoldMap _ (UnOp _)        = M.mempty
>     fvFoldMap _ (BinOp _)       = M.mempty
>     fvFoldMap _ (TyComp _)      = M.mempty