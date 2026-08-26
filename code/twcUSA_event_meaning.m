function meaning = twcUSA_event_meaning(code, caseID)
%% twcUSA_event_meaning
% 根据 TWC_USA 的 ExperimentalDescription.txt 返回事件代码含义。
%
% 输入：
%   code   - 四舍五入后的数字事件代码
%   caseID - 当前记录的 Case ID；数学题 1~20 的表达式依案例范围不同
%
% 输出：
%   meaning - 可直接写入事件表、图形标签和报告的文字说明

if isnan(code)
    meaning = "非数字事件代码";
    return;
end

if code == 23
    meaning = "TLR 光提示（light cue）";
elseif code == 29
    meaning = "TLR 声音提示（auditory cue）";
elseif code == 32
    meaning = "新脚本开始（new script started）";
elseif code == 64
    meaning = "音量降低（volume down）";
elseif code == 65
    meaning = "音量升高（volume up）";
elseif code >= 1 && code <= 20
    % Cases 01~08 和 Cases 09~33 使用了两套数学题表达式。
    if ~isnan(caseID) && caseID <= 8
        expressions = { ...
            '9-7','3+2','14-13','6+1','19-16', ...
            '1+1','5-2','1+4','15-10','3+3', ...
            '8-4','2+2','8-0','4+1','14-13', ...
            '2+4','16-13','3+1','10-8','1+0'};
    else
        expressions = { ...
            '9-7','3+1','8-7','1+2','9-6', ...
            '1+1','5-2','4-1','8-6','8-5', ...
            '2+2','2+1','3+0','1+0','7-4', ...
            '2+0','6-3','3-1','5-4','1+0'};
    end
    meaning = "数学题：" + string(expressions{code});
elseif code == 21 || code == 24
    meaning = "其他数值事件（当前实验说明未明确映射）";
else
    meaning = "其他数值事件（代码 " + string(code) + "）";
end
end

