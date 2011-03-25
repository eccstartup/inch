> {-# LANGUAGE TypeSynonymInstances, FlexibleInstances, FlexibleContexts,
>              TypeOperators #-}

> module PrettyPrinter where

> import Data.Foldable
> import Data.List
> import Text.PrettyPrint.HughesPJ

> import TyNum
> import Type
> import BwdFwd
> import Syntax
> import Kit


> data Size = ArgSize | AppSize | ArrSize | LamSize
>     deriving (Bounded, Eq, Ord, Show)

> class Pretty x where
>     pretty :: x -> Size -> Doc

> prettyLow :: Pretty x => x -> Doc
> prettyLow = flip pretty minBound

> prettyHigh :: Pretty x => x -> Doc
> prettyHigh = flip pretty maxBound

> wrapDoc :: Size -> Doc -> Size -> Doc
> wrapDoc dSize d curSize
>   | dSize > curSize  = parens d
>   | otherwise        = d

> prettyProgram :: Program -> Doc
> prettyProgram = vcat . intersperse (text " ") . map (prettyHigh . bimap fst id)


> renderMe :: Pretty a => a -> String
> renderMe x = renderStyle style{ribbonsPerLine=1.2, lineLength=80} (prettyHigh x)

> d1 <++> d2 = sep [d1, nest 2 d2]
> infix 2 <++>


> class Ord a => PrettyVar a where
>     prettyVar :: a -> Doc
>     injectVar :: String -> a


> instance PrettyVar String where
>     prettyVar = text
>     injectVar = id

> instance PrettyVar (String, Int) where
>     prettyVar (s, -1) = text s
>     prettyVar (s, n) = text s <> char '_' <> int n
>     injectVar s = (s, -1)


> instance Pretty Kind where
>     pretty Set            = const $ text "*"
>     pretty KindNum        = const $ text "Num"
>     pretty (KindArr k l)  = wrapDoc AppSize $
>         pretty k ArgSize <+> text "->" <+> pretty l AppSize

> instance Pretty Binder where
>     pretty Pi _   = text "pi"
>     pretty All _  = text "forall"

> instance PrettyVar a => Pretty (TyNum a) where
>     pretty (NumConst k)  = const $ integer k
>     pretty (NumVar a)    = const $ prettyVar a
>     pretty (m :+: NumConst k) | k < 0 = wrapDoc AppSize $ 
>         pretty m ArgSize <+> text "-" <+> integer (-k)
>     pretty (m :+: Neg n) = wrapDoc AppSize $ 
>         pretty m ArgSize <+> text "-" <+> pretty n ArgSize
>     pretty (Neg m :+: n) = wrapDoc AppSize $ 
>         pretty n ArgSize <+> text "-" <+> pretty m ArgSize
>     pretty (m :+: n) = wrapDoc AppSize $ 
>         pretty m ArgSize <+> text "+" <+> pretty n ArgSize
>     pretty (m :*: n) = wrapDoc AppSize $ 
>         pretty m ArgSize <+> text "*" <+> pretty n ArgSize
>     pretty (Neg n) = wrapDoc AppSize $
>         text "-" <+> pretty n ArgSize

> instance PrettyVar a => Pretty (Pred a) where
>     pretty (P c n m) = wrapDoc AppSize $
>         pretty n ArgSize <+> pretty c ArgSize <+> pretty m ArgSize

> instance Pretty Comparator where
>     pretty LS _ = text "<"
>     pretty LE _ = text "<=" 
>     pretty GR _ = text ">"
>     pretty GE _ = text ">="
>     pretty EL _ = text "~"

> instance Pretty BuiltinTyCon where
>     pretty Arr   _ = parens (text "->")
>     pretty NumTy _ = text "Integer"

> instance PrettyVar a => Pretty (Ty k a) where
>     pretty (TyVar k a)              = const $ prettyVar a
>     pretty (TyCon c)                = const $ text c
>     pretty (TyApp (TyApp (TyB Arr) s) t)  = wrapDoc ArrSize $ 
>         pretty s AppSize <+> text "->" <++> pretty t ArrSize
>     pretty (TyApp f s)  = wrapDoc AppSize $ 
>         pretty f AppSize <+> pretty s ArgSize
>     pretty (TyB b)          = pretty b
>     pretty (TyNum n) = pretty n
>     pretty (Bind b a k t) = prettyBind b (B0 :< (a, k)) $
>         alphaConvert [(a, a ++ "'")] (unbind (injectVar a) t)
>     pretty (Qual p t) = prettyQual (B0 :< p) t

> prettyBind :: PrettyVar a => Binder -> Bwd (String, Kind) ->
>     Ty k a -> Size -> Doc
> prettyBind b bs (Bind b' a k t) | b == b' = prettyBind b (bs :< (a, k)) $
>     alphaConvert [(a, a ++ "'")] (unbind (injectVar a) t)
> prettyBind b bs t = wrapDoc LamSize $ prettyHigh b
>         <+> prettyBits (trail bs)
>         <+> text "." <++> pretty t ArrSize
>   where
>     prettyBits []             = empty
>     prettyBits ((a, Set) : aks) = text a <+> prettyBits aks
>     prettyBits ((a, k) : aks) = parens (text a <+> text "::" <+> prettyHigh k) <+> prettyBits aks


> prettyQual :: PrettyVar a => Bwd (Pred a) -> Ty k a -> Size -> Doc
> prettyQual ps (Qual p t) = prettyQual (ps :< p) t
> prettyQual ps t = wrapDoc ArrSize $
>     prettyPreds (trail ps) <+> text "=>" <++> pretty t ArrSize
>   where
>     prettyPreds ps = hsep (punctuate (text ",") (map prettyHigh ps))

> instance (PrettyVar a, PrettyVar x) => Pretty (Tm k a x) where
>     pretty (TmVar x)    = const $ prettyVar x
>     pretty (TmCon s)    = const $ text s
>     pretty (TmInt k)    = const $ integer k
>     pretty (TmApp f s)  = wrapDoc AppSize $
>         pretty f AppSize <++> pretty s ArgSize
>     pretty (TmBrace n)  = const $ braces $ prettyHigh n 
>     pretty (Lam x t)   = prettyLam (text x) (unbind (injectVar x) t)
>     pretty (Let ds t)  = wrapDoc ArgSize $ text "let" <+> vcatSpacePretty ds $$ text "in" <+> prettyHigh t
>     pretty (t :? ty)   = wrapDoc ArrSize $ 
>         pretty t AppSize <+> text "::" <+> pretty ty maxBound

> prettyLam :: (PrettyVar a, PrettyVar x) => Doc -> Tm k a x -> Size -> Doc
> prettyLam d (Lam x t) = prettyLam (d <+> prettyVar x) (unbind (injectVar x) t)
> prettyLam d t = wrapDoc LamSize $
>         text "\\" <+> d <+> text "->" <+> pretty t AppSize

> instance (PrettyVar a, PrettyVar x) => Pretty (Decl k a x) where
>     pretty (DD d) = pretty d 
>     pretty (FD f) = pretty f

> instance (PrettyVar a, PrettyVar x) => Pretty (DataDecl k a x) where
>     pretty (DataDecl n k cs) _ = hang (text "data" <+> text n
>         <+> (if k /= Set then text "::" <+> prettyHigh k else empty)
>         <+> text "where") 2 $
>             vcat (map prettyHigh cs)

> instance (PrettyVar a, PrettyVar x) => Pretty (FunDecl k a x) where
>     pretty (FunDecl n Nothing ps) _ = vcat (map ((prettyVar n <+>) . prettyHigh) ps)
>     pretty (FunDecl n (Just ty) ps) _ = vcat $ (prettyVar n <+> text "::" <+> prettyHigh ty) : map ((prettyVar n <+>) . prettyHigh) ps


> instance (PrettyVar x, Pretty p) => Pretty (x ::: p) where
>   pretty (x ::: p) _ = prettyVar x <+> text "::" <+> prettyHigh p


> instance (PrettyVar a, PrettyVar x) => Pretty (Pat k a x) where
>     pretty (Pat vs NoGuard e) _ =
>         hsep (map prettyLow vs) <+> text "=" <++> prettyHigh e
>     pretty (Pat vs g e) _ =
>         hsep (map prettyLow vs) <+> text "|" <+> prettyHigh g
>                                     <+> text "=" <++> prettyHigh e

> instance (PrettyVar a, PrettyVar x) => Pretty (Grd k a x) where
>     pretty NoGuard       = const (text "otherwise")
>     pretty (ExpGuard t)  = pretty t
>     pretty (NumGuard p)  = const $ braces (fsepPretty p)


> instance (PrettyVar a, PrettyVar x) => Pretty (PatTerm k a x) where
>     pretty (PatVar x)    = const $ prettyVar x
>     pretty (PatCon c []) = const $ text c
>     pretty (PatCon "+" [a, b]) = wrapDoc AppSize $
>         prettyLow a <+> text "+" <+> prettyLow b
>     pretty (PatCon c ps) = wrapDoc AppSize $
>                                text c <+> hsep (map prettyLow ps)
>     pretty PatIgnore = const $ text "_"
>     pretty (PatBrace Nothing k)   = const $ braces $ integer k
>     pretty (PatBrace (Just a) 0)  = const $ braces $ prettyVar a
>     pretty (PatBrace (Just a) k)  = const $ braces $
>                                     prettyVar a <+> text "+" <+> integer k

> instance (PrettyVar a, Show a, Ord a) => Pretty (NormPred a) where
>     pretty p = pretty (reifyPred p)

> instance Pretty NormalNum where
>     pretty n _ = prettyHigh $ simplifyNum $ reifyNum n

> instance Pretty x => Pretty (Bwd x) where
>     pretty bs _ = fsep $ punctuate (text ",") (map prettyHigh (trail bs))

> instance Pretty x => Pretty (Fwd x) where
>     pretty bs _ = fsep $ punctuate (text ",") $ map prettyHigh $ Data.Foldable.foldr (:) [] bs


> fsepPretty xs  = fsep . punctuate (text ",") . map prettyHigh $ xs
> vcatSpacePretty xs  = vcat . intersperse (text " ") . map prettyHigh $ xs
> vcatPretty xs  = vcat . map prettyHigh $ xs