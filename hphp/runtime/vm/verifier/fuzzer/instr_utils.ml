open Hhbc_ast
module IS = Instruction_sequence

let rec num_fold f n acc =
  if n <= 0 then acc else num_fold f (n - 1) (f acc)

let rec rebalance_stk n (stk : string list) (req : string list) =
  if n = 0 then ([], []) else
  match List.hd req, rebalance_stk (n-1) stk (List.tl req) with
  | "C", (buf, extra) -> ILitConst (Int (Int64.of_int 1))::buf, "C"::extra
  | "V", (buf, extra) ->
    ILitConst (Int (Int64.of_int 1))::IBasic (Box)::buf, "V"::extra
  | "F", (buf, extra) ->
    ILitConst (Int (Int64.of_int 1))::ICall (FPassC n)::buf, "F"::extra
  | "R", (buf, extra) ->
    ILitConst (Int (Int64.of_int 1))::IBasic (BoxR)::buf,"R"::extra
  | "U", (buf, extra) -> ILitConst NullUninit::buf, "U"::extra
  | _ -> ([], []) (*Impossible*)

let rec empty_stk stk remaining =
  if List.length stk <= remaining then [] else
  match stk with
  | [] -> []
  | "C" :: t -> IBasic PopC :: empty_stk t remaining
  | "V" :: t -> IBasic PopV :: empty_stk t remaining
  | "R" :: t -> IBasic PopR :: empty_stk t remaining
  | "U" :: t -> IBasic PopU :: empty_stk t remaining
  | _ :: t -> empty_stk t (remaining - 1)

let produce flavor n = num_fold (fun acc -> flavor::acc) n []

(* Determines how an instruction changes the stack, and how many
   cells it consumes. Return format is (required, produced) *)
let stk_data : instruct -> string list * string list = function
  | IMutator UnsetL _
  | ICall FPushFuncD _
  | ICall FPushClsMethodD _
  | ICall FPushCufIter _
  | ICall FPushFuncU _
  | IIncludeEvalDefine DefFunc _
  | IIncludeEvalDefine DefClsNop _
  | IIncludeEvalDefine DefCls _
  | IIncludeEvalDefine DefTypeAlias _
  | IGenerator ContCheck _
  | IGet ClsRefGetL _                      -> [], []
  | ICall FPushObjMethod _                 -> ["C"; "C"], []
  | IOp Fatal _
  | IContFlow JmpZ _
  | IContFlow JmpNZ _
  | IContFlow Switch _
  | IContFlow SSwitch _
  | IContFlow RetC
  | IContFlow Throw
  | IGet ClsRefGetC _
  | IMutator UnsetG
  | IMutator UnsetN
  | IMutator InitProp _
  | ICall FPushFunc _
  | ICall FPushCuf _
  | ICall FPushCufF _
  | ICall FPushObjMethodD _
  | ICall DecodeCufIter _
  | IIterator IterInit _
  | IIterator IterInitK _
  | IIterator WIterInit _
  | IIterator WIterInitK _
  | IMisc StaticLocInit _
  | IBasic PopC                            -> ["C"], []
  | IFinal SetWithRefRML _
  | IBasic PopR                            -> ["R"], []
  | IBasic PopU                            -> ["U"], []
  | IContFlow RetV
  | IIterator MIterInit _
  | IIterator MIterInitK _
  | IBasic PopV                            -> ["V"], []
  | IGet CGetL2 _
  | IBasic Dup                             -> ["C"], ["C"; "C"]
  | IGet VGetN
  | IGet VGetS _
  | IGet VGetG
  | IBasic Box                             -> ["C"], ["V"]
  | IBasic Unbox                           -> ["V"], ["C"]
  | IMutator BindL _                       -> ["V"], ["V"]
  (*| IBasic BoxRNop*)
  | IBasic BoxR                            -> ["R"], ["V"]
  | IBasic UnboxRNop
  | IBasic UnboxR                          -> ["R"], ["C"]
  | IBasic RGetCNop                        -> ["C"], ["R"]
  | IMisc CGetCUNop                        -> ["U"], ["C"]
  | IMisc UGetCUNop                        -> ["C"], ["U"]
  | IGet VGetL _                           -> [], ["V"]
  | ILitConst NullUninit                   -> [], ["U"]
  | ICall FPassL _                         -> [], ["F"]
  | ILitConst NewVecArray n
  | ILitConst NewKeysetArray n
  (*| IOp ConcatN n *)
  | IFinal QueryM (n, _, _)
  | IFinal IncDecM (n, _, _)
  | IMisc MemoGet (n, _, _)
  | IMisc CreateCl (n, _)
  | ILitConst NewPackedArray n             -> produce "C" n, ["C"]
  | IFinal SetOpM (n, _, _)
  | IMisc MemoSet (n, _, _)
  | IFinal SetM (n, _)                     -> produce "C" (n + 1), ["C"]
  | IFinal FPassM (_, n, _)
  | IFinal VGetM (n, _)                    -> produce "C" n, ["V"]
  | IFinal UnsetM (n, _)                   -> produce "C" n, []
  | IFinal BindM (n, _)                    -> produce "V" (n + 1), ["V"]
  | ILitConst NewStructArray v             -> produce "C" (List.length v), ["C"]
  | IMisc Idx
  | IMisc ArrayIdx
  | ILitConst AddElemC                     -> ["C"; "C"; "C"], ["C"]
  | ILitConst AddElemV                     -> ["C"; "C"; "V"], ["C"]
  | IGet CGetL _
  | IGet PushL _
  | IGet CUGetL _
  | IIsset IssetL _
  | IIsset EmptyL _
  | IIsset IsTypeL _
  | IMutator IncDecL _
  | IMutator CheckProp _
  | IMisc This
  | IMisc BareThis _
  | IMisc StaticLoc _
  | IMisc Catch
  | IMisc GetMemoKeyL _
  | IGenerator CreateCont
  | IGenerator ContValid
  | IGenerator ConStarted
  | IGenerator ContKey
  | IGenerator ContGetReturn
  | ICall FPushCtor _
  | ICall FPushCtorD _
  | ICall FPushCtorI _
  | IGet CGetQuietL _                      -> [], ["C"]
  | IMutator SetN
  | IMutator SetG
  | IMutator SetOpN _
  | IMutator SetOpG _
  | IMutator SetOpS _
  | IMisc OODeclExists _
  | IGenerator YieldK                      -> ["C"; "C"], ["C"]
  | IMutator BindN
  | IMutator BindG
  | IMutator BindS _
  | ILitConst AddNewElemV                  -> ["C"; "V"], ["V"]
  | IOp Abs
  | IOp Not
  | IOp Floor
  | IOp Ceil
  | IOp Sqrt
  | IOp CastBool
  | IOp CastInt
  | IOp CastDouble
  | IOp CastString
  | IOp CastArray
  | IOp CastObject
  | IOp CastVec
  | IOp CastDict
  | IOp CastKeyset
  | IOp InstanceOf
  | IOp InstanceOfD _
  | IOp Print
  | IOp Clone
  | IOp Hhbc_ast.Exit
  | IBase BaseSC _
  | IBase BaseSL _
  | IGet _
  | IIsset _
  | IMutator _
  | IIncludeEvalDefine _
  | IMisc VerifyRetTypeC
  | IMisc AKExists
  | IGenerator _
  | IAsync _
  | ILitConst ColFromArray _               -> ["C"], ["C"]
  | IMisc VerifyRetTypeV                   -> ["V"], ["V"]
  | ICall FPushCufSafe _                   -> ["C"; "C"], ["C"; "C"]
  | ICall CufSafeArray                     -> ["C"; "C"; "R"], ["C"]
  | ICall CufSafeReturn                    -> ["C"; "C"; "R"], ["R"]
  | ICall FPassCW _
  | ICall FPassCE _
  | ICall FPassN _
  | ICall FPassG _
  | ICall FPassS _
  | ICall FPassC _                         -> ["C"], ["F"]
  | ICall FPassVNop _
  | ICall FPassV _                         -> ["V"], ["F"]
  | ICall FPassR _                         -> ["R"], ["F"]
  | ICall FCallArray                       -> ["F"], ["R"]
  | ILitConst NewPair
  | IOp _
  | ILitConst AddNewElemC                  -> ["C"; "C"], ["C"]
  | ICall FCallD (n, _, _)
  | ICall FCallAwait (n, _, _)
  | ICall FCallUnpack n
  | ICall FCall n                          -> produce "F" n, ["R"]
  | ICall FCallBuiltin (n, _, _)           -> produce "C" n, ["R"]
  | ILitConst _                            -> [], ["C"]
  | ICall _                                -> ["C"], []
  | _ -> [], []