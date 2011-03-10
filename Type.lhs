> {-# LANGUAGE DeriveFunctor, DeriveFoldable, DeriveTraversable,
>              GADTs, TypeOperators #-}

> module Type where

> import Data.Foldable
> import Data.Traversable

> import Kit
> import TyNum



> type Type             = Ty Kind TyName

> type SType            = Ty () String


> data Kind where
>     Set      :: Kind
>     KindNum  :: Kind
>     KindArr  :: Kind -> Kind -> Kind
>   deriving (Eq, Show)

> k1 ---> k2 = KindArr k1 k2
> infixr 5 --->

> targetsSet :: Kind -> Bool
> targetsSet Set            = True
> targetsSet KindNum        = False
> targetsSet (KindArr _ k)  = targetsSet k 






> data Binder where
>     Pi   :: Binder
>     All  :: Binder
>   deriving (Eq, Show)


> data BuiltinTyCon where
>     Arr    :: BuiltinTyCon
>     NumTy  :: BuiltinTyCon
>   deriving (Eq, Show)

> builtinKind :: BuiltinTyCon -> Kind
> builtinKind Arr    = Set ---> Set ---> Set
> builtinKind NumTy  = Set


> data Ty k a where
>     TyVar  :: k -> a -> Ty k a
>     TyCon  :: TyConName -> Ty k a
>     TyApp  :: Ty k a -> Ty k a -> Ty k a
>     TyB    :: BuiltinTyCon -> Ty k a
>     TyNum  :: TyNum a -> Ty k a
>     Bind   :: Binder -> String -> Kind -> Ty k (S a) -> Ty k a
>     Qual   :: Pred a -> Ty k a -> Ty k a
>   deriving (Eq, Show, Functor, Foldable, Traversable)

> mkTyCon :: String -> Ty k a
> mkTyCon "Integer"  = TyB NumTy
> mkTyCon "->"       = TyB Arr
> mkTyCon c     = TyCon c

> s --> t = TyApp (TyApp (TyB Arr) s) t
> infixr 5 -->

> (/->) :: Foldable f => f (Ty k a) -> Ty k a -> Ty k a
> ts /-> t = Data.Foldable.foldr (-->) t ts

> (/=>) :: Foldable f => f (Pred a) -> Ty k a -> Ty k a
> ps /=> t = Data.Foldable.foldr Qual t ps

> toNum :: Ty Kind a -> TyNum a
> toNum (TyNum n)          = n
> toNum (TyVar KindNum a)  = NumVar a
> toNum d                  = error $ "toNum: bad!"

Invariant: if a definition |a := Just d ::: KindNat| is in the
context, then |d| must be of the form |TyNum n| for some |n|.

> var :: Kind -> a -> Ty Kind a
> var KindNum  = TyNum . NumVar
> var k        = TyVar k

This is inefficient, but ensures Binds go outside Quals. Perhaps we
should use a better representation?

> simplifyTy :: Ty k a -> Ty k a
> simplifyTy (TyNum n)       = TyNum (simplifyNum n)
> simplifyTy (TyApp f s)     = TyApp (simplifyTy f) (simplifyTy s)
> simplifyTy (Bind b x k t)  = Bind b x k (simplifyTy t)
> simplifyTy (Qual p t)      = case simplifyTy t of
>     Bind b x k t'  -> Bind b x k $ simplifyTy (Qual (fmap S p) t')
>     t'             -> Qual (simplifyPred p) t'
> simplifyTy t               = t



> alphaConvert :: [(String, String)] -> Ty k a -> Ty k a
> alphaConvert xys (TyApp f s) = TyApp (alphaConvert xys f)
>                                      (alphaConvert xys s)
> alphaConvert xys (Bind b a k t) = case lookup a xys of
>     Just y   -> Bind b y k (alphaConvert ((a, y ++ "'") : xys) t)
>     Nothing  -> Bind b a k (alphaConvert xys t)
> alphaConvert xys t = t

> args :: Ty k a -> Int
> args (TyApp (TyApp (TyB Arr) s) t)  = succ $ args t
> args (Bind Pi x k t)                = succ $ args t
> args (Bind All x k t)               = args t
> args (Qual p t)                     = args t
> args _                              = 0

> splitArgs :: Ty k a -> ([Ty k a], Ty k a)
> splitArgs (TyApp (TyApp (TyB Arr) s) t) = (s:ss, ty)
>   where (ss, ty) = splitArgs t
> splitArgs t = ([], t)

> getTarget :: Ty k a -> Ty k a
> getTarget (TyApp (TyApp (TyB Arr) _) ty)  = getTarget ty
> getTarget t                               = t


> targets :: Eq a => Ty k a -> TyConName -> Bool
> targets (TyCon c)                 t | c == t = True
> targets (TyApp (TyApp (TyB Arr) _) ty)  t = targets ty t
> targets (TyApp f s)               t = targets f t
> targets (Bind b a k ty)           t = targets ty t
> targets (Qual p ty)               t = targets ty t
> targets _                         _ = False

> numToType :: NormalNum -> Type
> numToType  = TyNum . reifyNum
